extends GdUnitTestSuite
## Unit tests for WellSystem (model/well/gd_well_system.gd) and the ProjectTree
## expansion behind it.
##
## Built against a hand-authored two-project list rather than the shipped data,
## so retuning a project's curves or thresholds cannot turn the rules red.

const EPS := 0.000001

var _player: PlayerData
var _upgrades: UpgradeSystem
var _prestige: UpgradeSystem
var _production: ProductionSystem
var _ctx: ResolveContext
var _list: ProjectList
var _system: WellSystem

func before_test() -> void:
	_player = PlayerData.new()
	_player.water = BigNumber.from_value(0.0)
	_upgrades = UpgradeSystem.new()
	# The prestige track reaches the Well for exactly one thing: how far a project
	# may be funded. What is *open* is the Well's own business.
	_prestige = UpgradeSystem.new()
	_ctx = ResolveContext.new()
	_production = ProductionSystem.new(UpgradeSystem.new(), UpgradeSystem.new(),
		_prestige, _ctx, UpgradeSystem.new(), _upgrades)
	_list = _project_list()
	for def in ProjectTree.build(_list):
		_upgrades.register(def)
	_system = WellSystem.new(_player, _upgrades, _list, _prestige)

## Levels the depth perk, the way the Tide branch's effectless node does.
func _grant_depth(levels: int) -> void:
	var def := UpgradeDef.new()
	def.id = &"test_depth"
	def.max_level = levels
	_prestige.register(def)
	for _i in levels:
		assert_bool(_prestige.buy_with_points(&"test_depth", true)).is_true()

func _boon(display: String, unlock_at: int, stat: StringName, per_level: float) -> ProjectBoonDef:
	var effect := UpgradeEffectDef.new()
	effect.stat = stat
	effect.op = UpgradeEffectDef.Op.INCREASED
	effect.scope = UpgradeEffectDef.Scope.GLOBAL
	effect.per_level = per_level
	effect.level_scaling = UpgradeEffectDef.LevelScaling.LINEAR
	var boon := ProjectBoonDef.new()
	boon.display_name = display
	boon.description = display
	boon.unlock_at_level = unlock_at
	boon.effect = effect
	return boon

func _project_list() -> ProjectList:
	# Three rungs, deliberately not evenly spaced, so an off-by-one in the
	# threshold arithmetic cannot pass by coincidence.
	var open := ProjectDef.new()
	open.id = &"test_open"
	open.display_name = "Test Open"
	open.max_level = 10
	open.base_cost = BigNumber.from_value(10.0)
	open.cost_growth = 2.0
	var open_boons: Array[ProjectBoonDef] = [
		_boon("First", 1, &"water_production", 0.5),
		_boon("Second", 3, &"biomass_gain", 0.25),
		_boon("Third", 7, &"potency_production", 1.0),
	]
	open.boons = open_boons

	# Gated on the ladder's own progress, and priced differently: both curves are
	# authored per project.
	var gated := ProjectDef.new()
	gated.id = &"test_gated"
	gated.display_name = "Test Gated"
	gated.max_level = 4
	gated.base_cost = BigNumber.from_value(5.0)
	gated.cost_growth = 1.5
	gated.min_project_levels = 3
	var gated_boons: Array[ProjectBoonDef] = [_boon("Only", 1, &"tick_rate", -0.1)]
	gated.boons = gated_boons

	var projects: Array[ProjectDef] = [open, gated]
	var list := ProjectList.new()
	list.projects = projects
	list.max_level_perk_id = &"test_depth"
	list.max_level_per_perk_level = 3
	return list

# ---------------------------------------------------------------- funding

func test_a_fresh_project_starts_unfunded_and_costs_its_base() -> void:
	assert_int(_system.level(&"test_open")).is_zero()
	assert_float(_system.cost(&"test_open").to_float()).is_equal_approx(10.0, EPS)

func test_funding_debits_water_and_raises_the_level() -> void:
	_player.water = BigNumber.from_value(10.0)
	assert_bool(_system.invest(&"test_open")).is_true()
	assert_int(_system.level(&"test_open")).is_equal(1)
	assert_float(_player.water.to_float()).is_zero()

func test_funding_is_refused_when_the_water_is_short() -> void:
	_player.water = BigNumber.from_value(9.99)
	assert_bool(_system.can_invest(&"test_open")).is_false()
	assert_bool(_system.invest(&"test_open")).is_false()
	assert_int(_system.level(&"test_open")).is_zero()
	assert_float(_player.water.to_float()).is_equal_approx(9.99, EPS)

func test_the_price_climbs_with_the_level() -> void:
	_fund(&"test_open", 1)
	assert_float(_system.cost(&"test_open").to_float()).is_equal_approx(20.0, EPS)
	_fund(&"test_open", 1)
	assert_float(_system.cost(&"test_open").to_float()).is_equal_approx(40.0, EPS)

func test_a_maxed_project_refuses_further_funding_and_prices_at_zero() -> void:
	_fund(&"test_open", 10)
	assert_bool(_system.is_maxed(&"test_open")).is_true()
	assert_float(_system.cost(&"test_open").to_float()).is_zero()
	_player.water = BigNumber.from_value(1.0e9)
	assert_bool(_system.invest(&"test_open")).is_false()
	assert_int(_system.level(&"test_open")).is_equal(10)

# ---------------------------------------------------------------- gating

func test_a_gated_project_refuses_funding_until_the_well_is_funded_enough() -> void:
	_player.water = BigNumber.from_value(1000.0)
	assert_bool(_system.is_unlocked(&"test_gated")).is_false()
	assert_bool(_system.invest(&"test_gated")).is_false()

	_fund(&"test_open", 3)   # the gate counts fundings anywhere, not in itself

	assert_bool(_system.is_unlocked(&"test_gated")).is_true()
	_player.water = BigNumber.from_value(1000.0)
	assert_bool(_system.invest(&"test_gated")).is_true()

func test_an_ungated_project_is_open_from_the_start() -> void:
	assert_bool(_system.is_unlocked(&"test_open")).is_true()

func test_levels_until_unlock_counts_down_and_stops_at_zero() -> void:
	assert_int(_system.levels_until_unlock(&"test_gated")).is_equal(3)
	_fund(&"test_open", 2)
	assert_int(_system.levels_until_unlock(&"test_gated")).is_equal(1)
	_fund(&"test_open", 3)
	assert_int(_system.levels_until_unlock(&"test_gated")).is_zero()

func test_a_gate_reads_the_live_total_not_the_cached_projection() -> void:
	# PlayerData.well_project_levels is a projection a save load leaves stale
	# until sync_project_levels() runs. A gate read off it would open or shut
	# projects on whatever the last sync happened to say.
	_fund(&"test_open", 3)
	_player.well_project_levels = 0
	assert_bool(_system.is_unlocked(&"test_gated")).is_true()

# ---------------------------------------------------------------- depth perk

func test_without_the_perk_a_project_stops_at_its_authored_ceiling() -> void:
	assert_int(_system.max_level(&"test_open")).is_equal(10)
	assert_int(_system.extra_levels()).is_zero()

func test_the_depth_perk_raises_every_projects_ceiling() -> void:
	_grant_depth(2)
	assert_int(_system.extra_levels()).is_equal(6)
	assert_int(_system.max_level(&"test_open")).is_equal(16)
	assert_int(_system.max_level(&"test_gated")).is_equal(10)   # authored 4, +6

func test_a_maxed_project_becomes_fundable_again_when_the_perk_is_bought() -> void:
	_fund(&"test_open", 10)
	assert_bool(_system.is_maxed(&"test_open")).is_true()

	_grant_depth(1)

	assert_bool(_system.is_maxed(&"test_open")).is_false()
	_fund(&"test_open", 3)
	assert_int(_system.level(&"test_open")).is_equal(13)
	assert_bool(_system.is_maxed(&"test_open")).is_true()

func test_boons_keep_levelling_past_the_authored_ceiling() -> void:
	# The trap this guards: ProjectTree used to bake the authored ceiling into
	# each boon's UpgradeDef, so buy_with_points refused exactly the levels the
	# perk had been bought to allow - the project rose and its boons did not.
	_grant_depth(2)
	_fund(&"test_open", 16)
	assert_int(_system.boon_level(&"test_open", 0)).is_equal(16)
	assert_int(_system.boon_level(&"test_open", 1)).is_equal(14)   # opened at 3
	assert_int(_system.boon_level(&"test_open", 2)).is_equal(10)   # opened at 7

func test_a_list_with_no_depth_perk_adds_nothing() -> void:
	var bare := ProjectList.new()
	var projects: Array[ProjectDef] = [_list.projects[0]]
	bare.projects = projects
	var system := WellSystem.new(_player, _upgrades, bare, _prestige)
	_grant_depth(5)
	assert_int(system.extra_levels()).is_zero()
	assert_int(system.max_level(&"test_open")).is_equal(10)

# ---------------------------------------------------------------- boons

func test_only_the_first_boon_pays_out_at_level_one() -> void:
	_fund(&"test_open", 1)
	assert_bool(_system.is_boon_unlocked(&"test_open", 0)).is_true()
	assert_bool(_system.is_boon_unlocked(&"test_open", 1)).is_false()
	assert_int(_system.boon_level(&"test_open", 0)).is_equal(1)
	assert_int(_system.boon_level(&"test_open", 1)).is_zero()

func test_a_boon_takes_its_first_level_exactly_at_its_threshold() -> void:
	_fund(&"test_open", 2)
	assert_int(_system.boon_level(&"test_open", 1)).is_zero()
	_fund(&"test_open", 1)
	assert_bool(_system.is_boon_unlocked(&"test_open", 1)).is_true()
	assert_int(_system.boon_level(&"test_open", 1)).is_equal(1)

## The whole point of the ladder: a rung counts from where it opened, not from
## where the project started, so a late boon is worth less in total than an early
## one at the same project level.
func test_a_late_boon_counts_from_its_own_threshold() -> void:
	_fund(&"test_open", 8)
	assert_int(_system.boon_level(&"test_open", 0)).is_equal(8)
	assert_int(_system.boon_level(&"test_open", 1)).is_equal(6)   # opened at 3
	assert_int(_system.boon_level(&"test_open", 2)).is_equal(2)   # opened at 7

func test_a_boon_reaches_the_stat_it_names() -> void:
	_fund(&"test_open", 2)
	# Two levels of the first boon, +50% each, into the additive pool.
	assert_float(_production.modify_water_gain(BigNumber.from_value(1.0)).to_float()) \
		.is_equal_approx(2.0, EPS)
	# The second boon has not opened yet, so biomass is untouched.
	assert_float(_production.modify_biomass_gain(BigNumber.from_value(1.0)).to_float()) \
		.is_equal_approx(1.0, EPS)

func test_boon_levels_stop_at_their_own_ceiling() -> void:
	# A boon opening at 7 on a project capped at 10 has four levels in it.
	_fund(&"test_open", 10)
	assert_int(_system.boon_level(&"test_open", 2)).is_equal(4)

# ---------------------------------------------------------------- projection

func test_total_levels_sums_every_project_and_reaches_player_data() -> void:
	# Three into the open project is exactly what opens the gated one.
	_fund(&"test_open", 3)
	_fund(&"test_gated", 2)
	assert_int(_system.total_levels()).is_equal(5)
	assert_int(_player.well_project_levels).is_equal(5)

func test_sync_rebuilds_the_projection_after_a_load() -> void:
	_fund(&"test_open", 2)
	_player.well_project_levels = 0      # as a save load leaves it
	_system.sync_project_levels()
	assert_int(_player.well_project_levels).is_equal(2)

# ---------------------------------------------------------------- helpers

## Funds a project `times` over, topping the water up each time so the test is
## about the ladder rather than about affording it.
func _fund(project_id: StringName, times: int) -> void:
	for _i in times:
		_player.water = _system.cost(project_id)
		assert_bool(_system.invest(project_id)) \
			.override_failure_message("Funding '%s' was refused." % project_id).is_true()
