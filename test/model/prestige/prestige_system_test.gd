extends GdUnitTestSuite
## Unit tests for PrestigeSystem (model/prestige/gd_prestige_system.gd).
##
## A prestige is the one irreversible action in the game: it trades the whole
## run for biomass and there is no undo, so what it wipes and what it spares are
## both asserted explicitly.

const EPS := 0.000001

var _player: PlayerData
var _biomes_data: BiomesData
var _nodes: Array[MyceliumNode]
var _symbiosis: UpgradeSystem
var _biome_upgrades: UpgradeSystem
var _perks: UpgradeSystem
var _ctx: ResolveContext
var _production: ProductionSystem
var _biome_system: BiomeSystem
var _system: PrestigeSystem

func before_test() -> void:
	_player = PlayerData.new()
	_biomes_data = BiomesData.new()
	_nodes = _chain(3)
	_symbiosis = UpgradeSystem.new()
	_biome_upgrades = UpgradeSystem.new()
	_perks = UpgradeSystem.new()
	_ctx = ResolveContext.new()
	_production = ProductionSystem.new(_symbiosis, _biome_upgrades, _perks, _ctx)

	var biomes := load("res://data/biomes/all_biomes.tres") as BiomeList
	_biome_system = BiomeSystem.new(biomes, _biomes_data, _player, _nodes, _production,
		_symbiosis, _biome_upgrades, _perks, _ctx)
	_biome_system.unlock_free_biomes()

	_system = PrestigeSystem.new(_player, _biomes_data, _nodes, _production,
		_symbiosis, _biome_upgrades, _biome_system,
		load("res://data/prestige/res_prestige_curve.tres") as PrestigeCurveDef)

func _chain(tiers: int) -> Array[MyceliumNode]:
	var nodes: Array[MyceliumNode] = []
	for i in range(tiers):
		var node := MyceliumNode.new()
		node.node_id = i
		node.manual_nodes = 4
		node.auto_nodes = BigNumber.from_value(1000.0)
		nodes.append(node)
	return nodes

func _register(system: UpgradeSystem, id: StringName, level: int,
		effects: Array[UpgradeEffectDef] = []) -> void:
	var d := UpgradeDef.new()
	d.id = id
	d.effects = effects
	system.register(d)
	system.set_level_for_analysis(id, level)

func _biomass_effect(per_level: float) -> Array[UpgradeEffectDef]:
	var e := UpgradeEffectDef.new()
	e.stat = &"biomass_gain"
	e.per_level = per_level
	e.op = UpgradeEffectDef.Op.INCREASED
	e.scope = UpgradeEffectDef.Scope.GLOBAL
	return [e]

## Puts the run in a state a prestige is actually offered for. The payout is
## priced off what the run *produced*, so that is what this fills.
func _make_prestige_available() -> void:
	_biomes_data.unlock(PrestigeSystem.GATE_BIOME)
	_player.run_nutrients = BigNumber.from_value(1e6)

# ─── Gating ──────────────────────────────────────────────────────────────────

func test_prestige_is_gated_on_the_biome_however_rich_the_run_is() -> void:
	_player.run_nutrients = BigNumber.from_value(1e30)
	assert_bool(_biomes_data.is_unlocked(PrestigeSystem.GATE_BIOME)).is_false()
	assert_bool(_system.can_prestige()).is_false()

func test_prestige_is_refused_when_the_run_is_worth_nothing() -> void:
	_biomes_data.unlock(PrestigeSystem.GATE_BIOME)
	_player.run_nutrients = BigNumber.from_value(1.0)
	assert_float(_system.preview_biomass_gain().to_float()).is_zero()
	assert_bool(_system.can_prestige()).is_false()

func test_prestige_is_offered_once_gated_and_worth_something() -> void:
	_make_prestige_available()
	assert_bool(_system.can_prestige()).is_true()

func test_a_run_that_only_ties_the_best_is_refused() -> void:
	# The payout is a step function, so a run can sit on the same filled-area
	# count for a long time. Trading it again pays what the last one paid and
	# costs a whole run - which is the trade this gate exists to refuse.
	_make_prestige_available()
	_player.best_biomass_gain = _system.preview_biomass_gain()

	assert_bool(_system.can_prestige()).is_false()

func test_a_run_that_beats_the_best_is_offered() -> void:
	_make_prestige_available()
	_player.best_biomass_gain = _system.preview_biomass_gain()
	# One more filled nutrient area than the mark was set at.
	_player.run_nutrients = BigNumber.from_value(1e9)

	assert_bool(_system.can_prestige()).is_true()

func test_prestiging_raises_the_bar_for_the_next_run() -> void:
	_make_prestige_available()
	var gain := _system.preview_biomass_gain()

	_system.prestige()

	assert_float(_player.best_biomass_gain.to_float()).is_equal_approx(gain.to_float(), EPS)

func test_a_weaker_run_never_lowers_the_bar() -> void:
	_make_prestige_available()
	_player.best_biomass_gain = BigNumber.from_value(1e6)

	_system.prestige()

	assert_float(_player.best_biomass_gain.to_float()).is_equal_approx(1e6, EPS)

func test_the_gate_biome_is_one_the_authored_data_defines() -> void:
	# The key is a plain StringName, so a biome rename would silently make the
	# prestige tab unreachable rather than fail at load.
	assert_object(_biome_system.biome_def(PrestigeSystem.GATE_BIOME)).is_not_null()

# ─── Payout ──────────────────────────────────────────────────────────────────

func test_the_previewed_gain_is_what_biomass_actually_receives() -> void:
	_make_prestige_available()
	var previewed := _system.preview_biomass_gain()

	_system.prestige()

	assert_float(_player.biomass.to_float()).is_equal_approx(previewed.to_float(), EPS)

func test_the_gain_is_added_to_existing_biomass_not_replacing_it() -> void:
	_make_prestige_available()
	_player.biomass = BigNumber.from_value(100.0)
	var previewed := _system.preview_biomass_gain()

	_system.prestige()

	assert_float(_player.biomass.to_float()).is_equal_approx(100.0 + previewed.to_float(), EPS)

func test_biome_upgrades_and_perks_boost_the_gain() -> void:
	_make_prestige_available()
	var base := _system.preview_biomass_gain().to_float()

	_register(_biome_upgrades, &"BioBonus", 1, _biomass_effect(1.0))
	_register(_perks, &"PerkBonus", 1, _biomass_effect(1.0))

	# 1 * (1 + 1) biome, then 1 * (1 + 1) perks: the two tracks compound.
	assert_float(_system.preview_biomass_gain().to_float()).is_equal_approx(base * 4.0, EPS)

func test_symbiosis_never_boosts_the_gain_it_is_paying_for() -> void:
	_make_prestige_available()
	var base := _system.preview_biomass_gain().to_float()

	_register(_symbiosis, &"SymBonus", 1, _biomass_effect(9.0))

	assert_float(_system.preview_biomass_gain().to_float()).is_equal_approx(base, EPS)

# ─── Storage ladder discounts ────────────────────────────────────────────────

## The authored curve the system was handed, to assert the discounted copy left
## it alone. load() hands back the same cached Resource every caller shares,
## which is exactly why effective_curve() must not write into it.
func _authored_curve() -> PrestigeCurveDef:
	return load("res://data/prestige/res_prestige_curve.tres") as PrestigeCurveDef

func _ladder_effect(stat: StringName, per_level: float) -> Array[UpgradeEffectDef]:
	var e := UpgradeEffectDef.new()
	e.stat = stat
	e.per_level = per_level
	e.op = UpgradeEffectDef.Op.ADD
	e.scope = UpgradeEffectDef.Scope.GLOBAL
	return [e]

func test_a_tick_area_discount_makes_the_time_ladder_cheaper() -> void:
	_make_prestige_available()
	_player.tick_count = 60
	var before := _system.storage_report()

	_register(_perks, &"Compression", 30, _ladder_effect(&"tick_area_cost", -1.0))
	var after := _system.storage_report()

	assert_int(after["tick_areas"]).is_greater(before["tick_areas"])
	assert_bool((after["tick_next"] as BigNumber).lt(before["tick_next"])) \
		.override_failure_message("The next time area still costs %s, not less than %s." \
			% [after["tick_next"], before["tick_next"]]).is_true()

func test_a_nutrient_growth_discount_fills_more_nutrient_areas() -> void:
	_make_prestige_available()
	_player.run_nutrients = BigNumber.from_value(1e9)
	var before := _system.storage_report()

	_register(_perks, &"Densification", 100, _ladder_effect(&"nutrient_area_growth", -0.001))
	var after := _system.storage_report()

	assert_int(after["nutrient_areas"]).is_greater(before["nutrient_areas"])
	assert_bool((after["gain"] as BigNumber).gt(before["gain"])) \
		.override_failure_message("A cheaper nutrient ladder paid %s, no more than %s." \
			% [after["gain"], before["gain"]]).is_true()

func test_an_absurd_discount_stops_at_the_floor_instead_of_paying_the_ceiling() -> void:
	# Both floors guard the same failure: PrestigeCalculator.areas_filled()
	# reports max_areas for a ladder with no width or a growth at or below 1.0,
	# so an unclamped discount would stop being a discount and hand every run the
	# largest payout the curve can express.
	_make_prestige_available()
	_player.tick_count = 60
	_register(_perks, &"Overshoot", 1, _ladder_effect(&"tick_area_cost", -1000.0))
	_register(_perks, &"Collapse", 1, _ladder_effect(&"nutrient_area_growth", -1000.0))

	var curve := _system.effective_curve()
	assert_float(curve.tick_base().to_float()) \
		.is_equal_approx(PrestigeSystem.MIN_TICK_AREA_TICKS, EPS)
	assert_float(curve.nutrient_growth) \
		.is_equal_approx(PrestigeSystem.MIN_NUTRIENT_AREA_GROWTH, EPS)

	var report := _system.storage_report()
	assert_int(report["tick_areas"]).is_less(curve.max_areas)
	assert_int(report["nutrient_areas"]).is_less(curve.max_areas)

func test_the_discounted_curve_never_writes_back_into_the_authored_one() -> void:
	var authored := _authored_curve()
	var ticks := authored.tick_base().to_float()
	var growth := authored.nutrient_growth
	_register(_perks, &"Compression", 30, _ladder_effect(&"tick_area_cost", -1.0))
	_register(_perks, &"Densification", 100, _ladder_effect(&"nutrient_area_growth", -0.001))

	_system.effective_curve()

	assert_float(authored.tick_base().to_float()).is_equal_approx(ticks, EPS)
	assert_float(authored.nutrient_growth).is_equal_approx(growth, EPS)

# ─── What the reset wipes ────────────────────────────────────────────────────

func test_currencies_and_counters_are_reset() -> void:
	_make_prestige_available()
	_player.water = BigNumber.from_value(500.0)
	_player.tick_count = 9439

	_system.prestige()

	assert_float(_player.nutrients.to_float()).is_equal_approx(1.0, EPS)
	assert_float(_player.run_nutrients.to_float()).is_zero()
	assert_float(_player.water.to_float()).is_zero()
	assert_int(_player.tick_count).is_zero()
	assert_int(_player.prestige_count).is_equal(1)

func test_tier_zero_keeps_one_node_so_the_run_can_restart() -> void:
	# With every tier at zero nothing produces, and nutrients reset to 1 is not
	# enough to buy a node back: the save would be permanently stuck.
	_make_prestige_available()

	_system.prestige()

	assert_int(_nodes[0].manual_nodes).is_equal(1)
	for node in _nodes:
		assert_float(node.auto_nodes.to_float()) \
			.override_failure_message("Tier %d kept auto nodes." % node.node_id).is_zero()

func test_every_tier_above_zero_is_wiped() -> void:
	_make_prestige_available()

	_system.prestige()

	for node in _nodes:
		if node.node_id == 0:
			continue
		assert_int(node.manual_nodes) \
			.override_failure_message("Tier %d kept manual nodes." % node.node_id).is_zero()

func test_symbiosis_and_biome_upgrade_levels_are_wiped() -> void:
	_make_prestige_available()
	_register(_symbiosis, &"Sym", 5)
	_register(_biome_upgrades, &"Bio", 3)

	_system.prestige()

	assert_int(_symbiosis.level(&"Sym")).is_zero()
	assert_int(_biome_upgrades.level(&"Bio")).is_zero()

func test_perk_levels_survive_the_reset() -> void:
	# Perks are what the run is being traded for. Wiping them makes the whole
	# prestige loop a net loss.
	_make_prestige_available()
	_register(_perks, &"Perk", 4)

	_system.prestige()

	assert_int(_perks.level(&"Perk")).is_equal(4)

func test_well_project_levels_survive_the_reset() -> void:
	# Water is a run currency the reset wipes, but what it was spent on is
	# permanent - the same split crystals and boosts have. PrestigeSystem is not
	# even handed the project track, and this is what says that is deliberate.
	_make_prestige_available()
	var projects := UpgradeSystem.new()
	_register(projects, &"project_sluice_b0", 6)
	_player.well_project_levels = 6

	_system.prestige()

	assert_float(_player.water.to_float()).is_zero()
	assert_int(projects.level(&"project_sluice_b0")).is_equal(6)
	assert_int(_player.well_project_levels).is_equal(6)

func test_biomes_are_relocked_but_stay_reachable() -> void:
	_make_prestige_available()
	# Bought like any other biome now, so it has to be opened before a test about
	# relocking can say anything about it.
	_biomes_data.unlock(&"meadow")

	_system.prestige()

	assert_bool(_biomes_data.is_unlocked(PrestigeSystem.GATE_BIOME)).is_false()
	assert_bool(_biomes_data.is_ever_unlocked(PrestigeSystem.GATE_BIOME)).is_true()
	# The Meadow relocks with the rest of them - it is a bought biome too, and a
	# single nutrient is not a run's worth of progress to hand back.
	assert_bool(_biomes_data.is_unlocked(&"meadow")).is_false()
	assert_bool(_biomes_data.is_ever_unlocked(&"meadow")).is_true()

func test_a_second_prestige_starts_from_the_reset_run() -> void:
	# tick_count and nutrients both feed the gain, so a reset that missed either
	# would pay the same run out twice.
	_make_prestige_available()
	_system.prestige()
	var after_first := _player.biomass.to_float()

	assert_float(_system.preview_biomass_gain().to_float()).is_zero()
	assert_bool(_system.can_prestige()).is_false()

	_system.prestige()

	assert_float(_player.biomass.to_float()).is_equal_approx(after_first, EPS)
	assert_int(_player.prestige_count).is_equal(2)
