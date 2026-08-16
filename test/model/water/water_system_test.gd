extends GdUnitTestSuite
## Unit tests for WaterSystem (model/water/gd_water_system.gd).
##
## Built against hand-made upgrade tracks rather than the shipped data, so
## retuning an authored water upgrade cannot turn the rules red.

const EPS := 0.000001

var _player: PlayerData
var _biomes_data: BiomesData
var _boosts: UpgradeSystem
var _production: ProductionSystem
var _system: WaterSystem

func before_test() -> void:
	_player = PlayerData.new()
	_biomes_data = BiomesData.new()
	_boosts = UpgradeSystem.new()
	_production = ProductionSystem.new(UpgradeSystem.new(), UpgradeSystem.new(),
		UpgradeSystem.new(), ResolveContext.new(), _boosts)
	_system = WaterSystem.new(_player, _biomes_data, _production)

func _open_lake() -> void:
	_biomes_data.unlock(WaterSystem.LAKE_KEY)

## Registers one upgrade at `level` writing `per_level` into `stat`, so a test
## can move a water stat without depending on any authored .tres.
func _register(id: StringName, stat: StringName, op: UpgradeEffectDef.Op,
		per_level: float, level: int) -> void:
	var effect := UpgradeEffectDef.new()
	effect.stat = stat
	effect.op = op
	effect.scope = UpgradeEffectDef.Scope.GLOBAL
	effect.per_level = per_level
	effect.level_scaling = UpgradeEffectDef.LevelScaling.LINEAR
	var effects: Array[UpgradeEffectDef] = [effect]
	var def := UpgradeDef.new()
	def.id = id
	def.max_level = 0
	def.effects = effects
	_boosts.register(def)
	for _i in level:
		assert_bool(_boosts.buy_with_points(id, true)).is_true()

# ---------------------------------------------------------------- gating

func test_a_locked_lake_pumps_nothing() -> void:
	_system.handle_ticks(0, 1000)
	assert_float(_player.water.to_float()).is_zero()

func test_an_open_lake_pumps_once_per_interval() -> void:
	_open_lake()
	_system.handle_ticks(0, _system.interval())
	assert_float(_player.water.to_float()).is_equal_approx(WaterSystem.BASE_YIELD, EPS)

func test_a_sporation_relocking_the_lake_stops_the_pump() -> void:
	# BiomesData.reset() keeps ever_unlocked and clears the run's own set, which
	# is exactly the state a sporation leaves behind.
	_open_lake()
	_biomes_data.reset()
	assert_bool(_system.is_pumping()).is_false()
	_system.handle_ticks(0, 1000)
	assert_float(_player.water.to_float()).is_zero()

# ---------------------------------------------------------------- timing

func test_a_partial_interval_pays_nothing() -> void:
	_open_lake()
	_system.handle_ticks(0, _system.interval() - 1)
	assert_float(_player.water.to_float()).is_zero()

## The invariant the live timer, the offline catch-up and the simulator's strides
## all rest on: a span pays the same whether it is walked or jumped.
func test_a_stride_pays_exactly_what_walking_the_span_pays() -> void:
	_open_lake()
	var span := 137

	var walked := PlayerData.new()
	var walked_system := WaterSystem.new(walked, _biomes_data, _production)
	for tick in span:
		walked_system.handle_ticks(tick, 1)

	_system.handle_ticks(0, span)
	assert_float(_player.water.to_float()) \
		.is_equal_approx(walked.water.to_float(), EPS)

func test_a_stride_starting_mid_interval_only_counts_the_crossings_inside_it() -> void:
	_open_lake()
	var every := _system.interval()
	# From one tick past a pump to one tick short of the second one after it.
	_system.handle_ticks(every + 1, every)
	assert_float(_player.water.to_float()).is_equal_approx(WaterSystem.BASE_YIELD, EPS)

func test_no_ticks_pays_nothing() -> void:
	_open_lake()
	_system.handle_ticks(0, 0)
	_system.handle_ticks(0, -5)
	assert_float(_player.water.to_float()).is_zero()

# ---------------------------------------------------------------- stats

func test_water_production_multiplies_the_yield() -> void:
	_open_lake()
	_register(&"more_water", &"water_production", UpgradeEffectDef.Op.INCREASED, 0.5, 2)
	# INCREASED is the additive pool: two levels of +50% is x2.
	assert_float(_system.pump_yield().to_float()) \
		.is_equal_approx(WaterSystem.BASE_YIELD * 2.0, EPS)
	_system.handle_ticks(0, _system.interval())
	assert_float(_player.water.to_float()) \
		.is_equal_approx(WaterSystem.BASE_YIELD * 2.0, EPS)

func test_water_rate_shortens_the_interval() -> void:
	_register(&"faster_water", &"water_rate", UpgradeEffectDef.Op.ADD, -1.0, 4)
	assert_int(_system.interval()).is_equal(int(WaterSystem.BASE_INTERVAL) - 4)

func test_the_interval_is_clamped_away_from_zero() -> void:
	# A stacked discount far past the base must not reach an every-tick pump, and
	# must never divide by zero in the crossing count.
	_register(&"far_too_fast", &"water_rate", UpgradeEffectDef.Op.ADD, -100.0, 10)
	assert_int(_system.interval()).is_greater_equal(1)
	_open_lake()
	_system.handle_ticks(0, 5)
	assert_float(_player.water.to_float()).is_greater(0.0)

func test_ticks_until_pump_counts_down_to_the_interval() -> void:
	var every := _system.interval()
	assert_int(_system.ticks_until_pump(0)).is_equal(every)
	assert_int(_system.ticks_until_pump(1)).is_equal(every - 1)
	assert_int(_system.ticks_until_pump(every - 1)).is_equal(1)
	assert_int(_system.ticks_until_pump(every)).is_equal(every)
