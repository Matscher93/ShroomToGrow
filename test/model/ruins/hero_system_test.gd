extends GdUnitTestSuite
## Unit tests for HeroSystem (model/ruins/gd_hero_system.gd).
##
## Built against a hand-authored two-hero roster rather than the shipped
## data, so retuning a hero's costs or affinities cannot turn the rules red.

const EPS := 0.000001

var _player: PlayerData
var _upgrades: UpgradeSystem
var _production: ProductionSystem
var _ctx: ResolveContext
var _data: RuinsData
var _system: HeroSystem

func before_test() -> void:
	_player = PlayerData.new()
	_player.relics = BigNumber.from_value(1000.0)
	_upgrades = UpgradeSystem.new()
	_ctx = ResolveContext.new()
	_production = ProductionSystem.new(UpgradeSystem.new(), UpgradeSystem.new(),
		UpgradeSystem.new(), _ctx, UpgradeSystem.new(), UpgradeSystem.new(),
		UpgradeSystem.new(), UpgradeSystem.new(), _upgrades)
	_data = RuinsData.new()
	_system = HeroSystem.new(_data, _player, _hero_list(), _production)

# ─── Fixtures ────────────────────────────────────────────────────────────────

func _hero_list() -> HeroList:
	var relics := CurrencyDef.new()
	relics.currency_type = CurrencyTypes.Types.RELICS

	var specialist := HeroDef.new()
	specialist.id = &"specialist"
	specialist.display_name = "Specialist"
	specialist.speed_per_level = 0.10
	specialist.yield_per_level = 0.20
	specialist.base_level_cap = 3
	specialist.min_missions_completed = 0
	specialist.recruit_currency = relics
	specialist.recruit_cost = BigNumber.from_value(10.0)
	specialist.level_currency = relics
	specialist.level_base_cost = BigNumber.from_value(20.0)
	specialist.level_cost_growth = 2.0

	var latecomer := HeroDef.new()
	latecomer.id = &"latecomer"
	latecomer.display_name = "Latecomer"
	latecomer.base_level_cap = 3
	latecomer.min_missions_completed = 5
	latecomer.recruit_currency = relics
	latecomer.recruit_cost = BigNumber.from_value(10.0)
	latecomer.level_currency = relics
	latecomer.level_base_cost = BigNumber.from_value(20.0)
	latecomer.level_cost_growth = 2.0

	var list := HeroList.new()
	list.heroes = [specialist, latecomer]
	return list

func _grant_level_cap(levels: int, target: StringName) -> void:
	var effect := UpgradeEffectDef.new()
	effect.stat = &"hero_level_cap"
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

func test_recruiting_costs_its_currency_and_lands_at_level_one() -> void:
	assert_bool(_system.recruit(&"specialist")).is_true()
	assert_int(_system.level(&"specialist")).is_equal(1)
	assert_bool(_player.relics.equals(BigNumber.from_value(990.0))).is_true()

func test_a_hero_cannot_be_recruited_twice() -> void:
	assert_bool(_system.recruit(&"specialist")).is_true()
	assert_bool(_system.can_recruit(&"specialist")).is_false()
	assert_bool(_system.recruit(&"specialist")).is_false()

func test_a_short_balance_refuses_the_recruit_and_charges_nothing() -> void:
	_player.relics = BigNumber.from_value(1.0)
	assert_bool(_system.recruit(&"specialist")).is_false()
	assert_int(_system.level(&"specialist")).is_equal(0)
	assert_bool(_player.relics.equals(BigNumber.from_value(1.0))).is_true()

func test_a_locked_hero_cannot_be_recruited() -> void:
	assert_bool(_system.is_unlocked(&"latecomer")).is_false()
	assert_int(_system.missions_until_unlock(&"latecomer")).is_equal(5)
	assert_bool(_system.recruit(&"latecomer")).is_false()
	_data.missions_completed = 5
	assert_bool(_system.is_unlocked(&"latecomer")).is_true()
	assert_bool(_system.recruit(&"latecomer")).is_true()

# ─── Levelling up ──────────────────────────────────────────────────────────────

func test_the_first_level_up_costs_the_authored_base() -> void:
	_system.recruit(&"specialist")
	assert_bool(_system.level_cost(&"specialist").equals(BigNumber.from_value(20.0))).is_true()
	assert_bool(_system.level_up(&"specialist")).is_true()
	assert_int(_system.level(&"specialist")).is_equal(2)
	assert_bool(_player.relics.equals(BigNumber.from_value(970.0))).is_true()

func test_each_level_costs_growth_times_the_last() -> void:
	_system.recruit(&"specialist")
	_system.level_up(&"specialist")
	assert_bool(_system.level_cost(&"specialist").equals(BigNumber.from_value(40.0))).is_true()

func test_a_hero_stops_at_its_authored_ceiling() -> void:
	_system.recruit(&"specialist")
	_system.level_up(&"specialist")
	_system.level_up(&"specialist")
	assert_int(_system.level(&"specialist")).is_equal(3)
	assert_bool(_system.is_maxed(&"specialist")).is_true()
	assert_bool(_system.level_up(&"specialist")).is_false()

func test_a_level_cap_effect_lifts_the_ceiling() -> void:
	_grant_level_cap(2, &"")
	assert_int(_system.level_cap(&"specialist")).is_equal(5)
	assert_int(_system.level_cap(&"latecomer")).is_equal(5)

## Scoped by hero id, so a perk can lift one thrall without lifting the rest.
func test_a_scoped_level_cap_effect_lifts_only_its_hero() -> void:
	_grant_level_cap(2, &"specialist")
	assert_int(_system.level_cap(&"specialist")).is_equal(5)
	assert_int(_system.level_cap(&"latecomer")).is_equal(3)

func test_a_hero_out_on_a_mission_cannot_be_levelled_up() -> void:
	_system.recruit(&"specialist")
	_data.add(&"dig", &"specialist", 0.0, 100.0, [])
	assert_bool(_system.is_busy(&"specialist")).is_true()
	assert_bool(_system.can_level_up(&"specialist")).is_false()
	assert_bool(_system.level_up(&"specialist")).is_false()

# ─── Bonuses ─────────────────────────────────────────────────────────────────

func test_level_scales_speed_and_yield_linearly() -> void:
	_system.recruit(&"specialist")
	assert_float(_system.speed_multiplier(&"specialist")).is_equal_approx(1.10, EPS)
	assert_float(_system.yield_multiplier(&"specialist")).is_equal_approx(1.20, EPS)
	_system.level_up(&"specialist")
	assert_float(_system.speed_multiplier(&"specialist")).is_equal_approx(1.20, EPS)
	assert_float(_system.yield_multiplier(&"specialist")).is_equal_approx(1.40, EPS)

# ─── Selection ───────────────────────────────────────────────────────────────

## A chain belongs to exactly one hero, so there is never a list to pick from -
## only "is this one free". What a hero is levelled *for* is its chain's own
## gates, which is MissionSystem's business rather than this one's.
func test_a_hero_is_available_once_recruited_and_idle() -> void:
	assert_bool(_system.is_available(&"specialist")).is_false()
	_system.recruit(&"specialist")
	assert_bool(_system.is_available(&"specialist")).is_true()
	_data.add(&"dig", &"specialist", 0.0, 100.0, [])
	assert_bool(_system.is_available(&"specialist")).is_false()

## The last hero costs all three currencies at once, and a short third must not
## leave the player charged for the first two.
func test_a_multi_currency_recruit_is_all_or_nothing() -> void:
	var def := _system.hero_def(&"latecomer")
	def.min_missions_completed = 0
	var ichor := CurrencyDef.new()
	ichor.currency_type = CurrencyTypes.Types.ICHOR
	var extra := MissionPayoutDef.new()
	extra.currency = ichor
	extra.amount = BigNumber.new(5.0, 2)     # 500, and the player has none
	def.extra_recruit_costs = [extra] as Array[MissionPayoutDef]

	assert_int(_system.recruit_prices(&"latecomer").size()).is_equal(2)
	assert_bool(_system.can_recruit(&"latecomer")).is_false()
	assert_bool(_system.recruit(&"latecomer")).is_false()
	assert_int(_system.level(&"latecomer")).is_zero()
	assert_float(_player.relics.to_float()).is_equal_approx(1000.0, EPS)

	_player.ichor = BigNumber.from_value(500.0)
	assert_bool(_system.recruit(&"latecomer")).is_true()
	assert_float(_player.relics.to_float()).is_equal_approx(990.0, EPS)
	assert_float(_player.ichor.to_float()).is_equal_approx(0.0, EPS)
