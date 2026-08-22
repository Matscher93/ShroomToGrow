extends GdUnitTestSuite
## Unit tests for CreatureSystem (model/ruins/gd_creature_system.gd).
##
## Built against a hand-authored two-creature roster rather than the shipped
## data, so retuning a creature's costs or affinities cannot turn the rules red.

const EPS := 0.000001

var _player: PlayerData
var _upgrades: UpgradeSystem
var _production: ProductionSystem
var _ctx: ResolveContext
var _data: RuinsData
var _system: CreatureSystem

func before_test() -> void:
	_player = PlayerData.new()
	_player.relics = BigNumber.from_value(1000.0)
	_upgrades = UpgradeSystem.new()
	_ctx = ResolveContext.new()
	_production = ProductionSystem.new(UpgradeSystem.new(), UpgradeSystem.new(),
		UpgradeSystem.new(), _ctx, UpgradeSystem.new(), UpgradeSystem.new(),
		UpgradeSystem.new(), UpgradeSystem.new(), _upgrades)
	_data = RuinsData.new()
	_system = CreatureSystem.new(_data, _player, _creature_list(), _production)

# ─── Fixtures ────────────────────────────────────────────────────────────────

func _creature_list() -> CreatureList:
	var relics := CurrencyDef.new()
	relics.currency_type = CurrencyTypes.Types.RELICS

	var specialist := CreatureDef.new()
	specialist.id = &"specialist"
	specialist.display_name = "Specialist"
	specialist.affinity = [&"dig"] as Array[StringName]
	specialist.speed_per_rank = 0.10
	specialist.yield_per_rank = 0.20
	specialist.affinity_bonus = 0.50
	specialist.base_rank_cap = 3
	specialist.min_missions_completed = 0
	specialist.recruit_currency = relics
	specialist.recruit_cost = BigNumber.from_value(10.0)
	specialist.rank_currency = relics
	specialist.rank_base_cost = BigNumber.from_value(20.0)
	specialist.rank_cost_growth = 2.0

	var latecomer := CreatureDef.new()
	latecomer.id = &"latecomer"
	latecomer.display_name = "Latecomer"
	latecomer.base_rank_cap = 3
	latecomer.min_missions_completed = 5
	latecomer.recruit_currency = relics
	latecomer.recruit_cost = BigNumber.from_value(10.0)
	latecomer.rank_currency = relics
	latecomer.rank_base_cost = BigNumber.from_value(20.0)
	latecomer.rank_cost_growth = 2.0

	var list := CreatureList.new()
	list.creatures = [specialist, latecomer]
	return list

func _grant_rank_cap(levels: int, target: StringName) -> void:
	var effect := UpgradeEffectDef.new()
	effect.stat = &"creature_rank_cap"
	effect.op = UpgradeEffectDef.Op.ADD
	effect.per_level = 1.0
	if not target.is_empty():
		effect.scope = UpgradeEffectDef.Scope.NODE
		effect.target = target
	var def := UpgradeDef.new()
	def.id = &"deeper"
	def.max_level = levels
	def.effects = [effect]
	_upgrades.register(def)
	for _i in levels:
		assert_bool(_upgrades.buy_with_points(&"deeper", true)).is_true()

# ─── Recruiting ──────────────────────────────────────────────────────────────

func test_recruiting_costs_its_currency_and_lands_at_rank_one() -> void:
	assert_bool(_system.recruit(&"specialist")).is_true()
	assert_int(_system.rank(&"specialist")).is_equal(1)
	assert_bool(_player.relics.equals(BigNumber.from_value(990.0))).is_true()

func test_a_creature_cannot_be_recruited_twice() -> void:
	assert_bool(_system.recruit(&"specialist")).is_true()
	assert_bool(_system.can_recruit(&"specialist")).is_false()
	assert_bool(_system.recruit(&"specialist")).is_false()

func test_a_short_balance_refuses_the_recruit_and_charges_nothing() -> void:
	_player.relics = BigNumber.from_value(1.0)
	assert_bool(_system.recruit(&"specialist")).is_false()
	assert_int(_system.rank(&"specialist")).is_equal(0)
	assert_bool(_player.relics.equals(BigNumber.from_value(1.0))).is_true()

func test_a_locked_creature_cannot_be_recruited() -> void:
	assert_bool(_system.is_unlocked(&"latecomer")).is_false()
	assert_int(_system.missions_until_unlock(&"latecomer")).is_equal(5)
	assert_bool(_system.recruit(&"latecomer")).is_false()
	_data.missions_completed = 5
	assert_bool(_system.is_unlocked(&"latecomer")).is_true()
	assert_bool(_system.recruit(&"latecomer")).is_true()

# ─── Ranking up ──────────────────────────────────────────────────────────────

func test_the_first_rank_up_costs_the_authored_base() -> void:
	_system.recruit(&"specialist")
	assert_bool(_system.rank_cost(&"specialist").equals(BigNumber.from_value(20.0))).is_true()
	assert_bool(_system.rank_up(&"specialist")).is_true()
	assert_int(_system.rank(&"specialist")).is_equal(2)
	assert_bool(_player.relics.equals(BigNumber.from_value(970.0))).is_true()

func test_each_rank_costs_growth_times_the_last() -> void:
	_system.recruit(&"specialist")
	_system.rank_up(&"specialist")
	assert_bool(_system.rank_cost(&"specialist").equals(BigNumber.from_value(40.0))).is_true()

func test_a_creature_stops_at_its_authored_ceiling() -> void:
	_system.recruit(&"specialist")
	_system.rank_up(&"specialist")
	_system.rank_up(&"specialist")
	assert_int(_system.rank(&"specialist")).is_equal(3)
	assert_bool(_system.is_maxed(&"specialist")).is_true()
	assert_bool(_system.rank_up(&"specialist")).is_false()

func test_a_rank_cap_effect_lifts_the_ceiling() -> void:
	_grant_rank_cap(2, &"")
	assert_int(_system.rank_cap(&"specialist")).is_equal(5)
	assert_int(_system.rank_cap(&"latecomer")).is_equal(5)

## Scoped by creature id, so a perk can lift one thrall without lifting the rest.
func test_a_scoped_rank_cap_effect_lifts_only_its_creature() -> void:
	_grant_rank_cap(2, &"specialist")
	assert_int(_system.rank_cap(&"specialist")).is_equal(5)
	assert_int(_system.rank_cap(&"latecomer")).is_equal(3)

func test_a_creature_out_on_a_mission_cannot_be_ranked_up() -> void:
	_system.recruit(&"specialist")
	_data.add(&"dig", &"specialist", 0.0, 100.0, [])
	assert_bool(_system.is_busy(&"specialist")).is_true()
	assert_bool(_system.can_rank_up(&"specialist")).is_false()
	assert_bool(_system.rank_up(&"specialist")).is_false()

# ─── Bonuses ─────────────────────────────────────────────────────────────────

func test_rank_scales_speed_and_yield_linearly() -> void:
	_system.recruit(&"specialist")
	assert_float(_system.speed_multiplier(&"specialist", &"other")).is_equal_approx(1.10, EPS)
	assert_float(_system.yield_multiplier(&"specialist", &"other")).is_equal_approx(1.20, EPS)
	_system.rank_up(&"specialist")
	assert_float(_system.speed_multiplier(&"specialist", &"other")).is_equal_approx(1.20, EPS)
	assert_float(_system.yield_multiplier(&"specialist", &"other")).is_equal_approx(1.40, EPS)

## Affinity rides on top of the rank rate rather than being folded into it, so a
## rank-1 specialist already beats a rank-1 generalist on its own missions.
func test_affinity_multiplies_on_top_of_the_rank_rate() -> void:
	_system.recruit(&"specialist")
	assert_bool(_system.has_affinity(&"specialist", &"dig")).is_true()
	assert_float(_system.speed_multiplier(&"specialist", &"dig")).is_equal_approx(1.65, EPS)
	assert_float(_system.yield_multiplier(&"specialist", &"dig")).is_equal_approx(1.80, EPS)

func test_a_creature_with_no_affinity_gets_no_bonus_anywhere() -> void:
	_data.missions_completed = 5
	_system.recruit(&"latecomer")
	assert_bool(_system.has_affinity(&"latecomer", &"dig")).is_false()

# ─── Selection ───────────────────────────────────────────────────────────────

func test_only_idle_recruited_creatures_of_rank_are_offered() -> void:
	var mission := MissionDef.new()
	mission.id = &"dig"
	mission.min_creature_rank = 2

	assert_int(_system.available_for(mission).size()).is_equal(0)
	_system.recruit(&"specialist")
	# Recruited but only rank 1, and the mission wants 2.
	assert_int(_system.available_for(mission).size()).is_equal(0)
	_system.rank_up(&"specialist")
	assert_int(_system.available_for(mission).size()).is_equal(1)
	_data.add(&"dig", &"specialist", 0.0, 100.0, [])
	assert_int(_system.available_for(mission).size()).is_equal(0)
