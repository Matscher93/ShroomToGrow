extends GdUnitTestSuite
## Unit tests for WorkerSystem (model/ruins/gd_worker_system.gd) - the pool, its
## three-currency price, and how many of it one farm will hold.
##
## Built against a hand-authored cost rather than the shipped one, so retuning
## what a worker costs cannot turn the rules red.

const EPS := 0.000001

var _player: PlayerData
var _data: RuinsData
var _upgrades: UpgradeSystem
var _production: ProductionSystem
var _ctx: ResolveContext
var _system: WorkerSystem

func before_test() -> void:
	_player = PlayerData.new()
	_player.relics = BigNumber.from_value(1000.0)
	_player.ichor = BigNumber.from_value(1000.0)
	_player.glyphs = BigNumber.from_value(1000.0)
	_data = RuinsData.new()
	_upgrades = UpgradeSystem.new()
	_ctx = ResolveContext.new()
	_production = ProductionSystem.new(UpgradeSystem.new(), UpgradeSystem.new(),
		UpgradeSystem.new(), _ctx, UpgradeSystem.new(), UpgradeSystem.new(),
		UpgradeSystem.new(), UpgradeSystem.new(), _upgrades)
	_system = WorkerSystem.new(_data, _player, _cost(), _production)

# ─── Fixtures ────────────────────────────────────────────────────────────────

func _price(type: CurrencyTypes.Types, mantissa: float, exponent: int) -> MissionPayoutDef:
	var currency := CurrencyDef.new()
	currency.currency_type = type
	var price := MissionPayoutDef.new()
	price.currency = currency
	price.amount = BigNumber.new(mantissa, exponent)
	return price

## 100 relics, 50 ichor and 10 glyphs, doubling with every worker owned.
func _cost() -> WorkerCostDef:
	var cost := WorkerCostDef.new()
	cost.prices = [
		_price(CurrencyTypes.Types.RELICS, 1.0, 2),
		_price(CurrencyTypes.Types.ICHOR, 5.0, 1),
		_price(CurrencyTypes.Types.GLYPHS, 1.0, 1),
	] as Array[MissionPayoutDef]
	cost.cost_growth = 2.0
	return cost

func _grant_room(levels: int, target := &"") -> void:
	var effect := UpgradeEffectDef.new()
	effect.stat = &"workers_per_farm"
	effect.op = UpgradeEffectDef.Op.ADD
	effect.per_level = 1.0
	if not target.is_empty():
		effect.scope = UpgradeEffectDef.Scope.NODE
		effect.target = target
	var def := UpgradeDef.new()
	def.id = &"room"
	def.max_level = levels
	def.effects = [effect] as Array[UpgradeEffectDef]
	_upgrades.register(def)
	for _i in levels:
		assert_bool(_upgrades.buy_with_points(&"room", true)).is_true()

func _amount(field: StringName) -> float:
	for price: Dictionary in _system.prices():
		if price["field"] == field:
			return (price["amount"] as BigNumber).to_float()
	return -1.0

# ─── The price ───────────────────────────────────────────────────────────────

## A worker is priced in all three currencies at once, which is what makes the
## whole roster worth walking rather than only the chain paying for what is
## wanted next.
func test_the_first_worker_costs_the_authored_base_in_every_currency() -> void:
	assert_int(_system.prices().size()).is_equal(3)
	assert_float(_amount(&"relics")).is_equal_approx(100.0, EPS)
	assert_float(_amount(&"ichor")).is_equal_approx(50.0, EPS)
	assert_float(_amount(&"glyphs")).is_equal_approx(10.0, EPS)

## Every row grows on the same owned count, so the three stay in the ratio they
## were authored in however many have been hired.
func test_every_row_grows_with_the_workers_owned() -> void:
	_data.workers_owned = 3
	assert_float(_amount(&"relics")).is_equal_approx(800.0, EPS)
	assert_float(_amount(&"ichor")).is_equal_approx(400.0, EPS)
	assert_float(_amount(&"glyphs")).is_equal_approx(80.0, EPS)

# ─── Hiring ──────────────────────────────────────────────────────────────────

func test_hiring_spends_every_currency_and_raises_the_pool() -> void:
	assert_bool(_system.hire()).is_true()
	assert_int(_system.owned()).is_equal(1)
	assert_float(_player.relics.to_float()).is_equal_approx(900.0, EPS)
	assert_float(_player.ichor.to_float()).is_equal_approx(950.0, EPS)
	assert_float(_player.glyphs.to_float()).is_equal_approx(990.0, EPS)

## The half of the three-currency price that matters: a short third currency must
## not leave the player charged for the first two.
func test_a_short_third_currency_charges_nothing_at_all() -> void:
	_player.glyphs = BigNumber.from_value(1.0)
	assert_bool(_system.can_hire()).is_false()
	assert_bool(_system.hire()).is_false()
	assert_int(_system.owned()).is_zero()
	assert_float(_player.relics.to_float()).is_equal_approx(1000.0, EPS)
	assert_float(_player.ichor.to_float()).is_equal_approx(1000.0, EPS)
	assert_float(_player.glyphs.to_float()).is_equal_approx(1.0, EPS)

func test_hiring_stops_when_the_curve_outruns_the_balances() -> void:
	assert_bool(_system.hire()).is_true()   # 100 / 50 / 10
	assert_bool(_system.hire()).is_true()   # 200 / 100 / 20
	assert_bool(_system.hire()).is_true()   # 400 / 200 / 40
	assert_bool(_system.can_hire()).is_false()   # 800 relics, only 300 left
	assert_int(_system.owned()).is_equal(3)

# ─── The pool ────────────────────────────────────────────────────────────────

## Where a worker is, is read off the board rather than tracked beside it: a
## second tally is a second thing that can disagree.
func test_idle_is_what_the_board_is_not_already_using() -> void:
	_data.workers_owned = 5
	assert_int(_system.idle()).is_equal(5)
	_data.add(&"plot", &"", 0.0, 60.0, [], true, 2)
	assert_int(_system.assigned()).is_equal(2)
	assert_int(_system.idle()).is_equal(3)

## An expedition carries a hero rather than workers, so it must not count against
## the pool.
func test_an_expedition_uses_no_workers() -> void:
	_data.workers_owned = 4
	_data.add(&"errand", &"digger", 0.0, 60.0, [])
	assert_int(_system.assigned()).is_zero()
	assert_int(_system.idle()).is_equal(4)

# ─── The per-farm ceiling ────────────────────────────────────────────────────

func test_a_farm_starts_at_the_base_ceiling() -> void:
	assert_int(_system.max_per_farm(&"plot")).is_equal(WorkerSystem.BASE_WORKERS_PER_FARM)

func test_a_global_effect_widens_every_farm() -> void:
	_grant_room(2)
	assert_int(_system.max_per_farm(&"plot")).is_equal(3)
	assert_int(_system.max_per_farm(&"other")).is_equal(3)

## Scoped by mission id, so an expedition reward can widen one farm without
## widening the rest - the shape hero_level_bonus() reads per hero.
func test_a_scoped_effect_widens_only_its_own_farm() -> void:
	_grant_room(2, &"plot")
	assert_int(_system.max_per_farm(&"plot")).is_equal(3)
	assert_int(_system.max_per_farm(&"other")).is_equal(1)

## What a card's + button reads: the ceiling, capped by what is actually free.
func test_the_most_available_is_the_smaller_of_the_ceiling_and_the_pool() -> void:
	_grant_room(9)
	_data.workers_owned = 3
	assert_int(_system.most_available_for(&"plot", 0)).is_equal(3)
	_data.workers_owned = 40
	assert_int(_system.most_available_for(&"plot", 0)).is_equal(10)

## Workers already on the farm count towards what it may hold, or a full farm
## could never be re-set to the size it already is.
func test_workers_already_here_count_towards_what_is_available() -> void:
	_grant_room(3)
	_data.workers_owned = 2
	_data.add(&"plot", &"", 0.0, 60.0, [], true, 2)
	assert_int(_system.idle()).is_zero()
	assert_int(_system.most_available_for(&"plot", 2)).is_equal(2)
