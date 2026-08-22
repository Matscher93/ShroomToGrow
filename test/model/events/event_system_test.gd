extends GdUnitTestSuite
## Unit tests for EventSystem (model/events/gd_event_system.gd).
##
## Built against hand-made defs rather than the shipped pool, so retuning an
## authored event cannot turn the rules red. The rng is seeded in before_test so
## every spawn assertion is reproducible.

const EPS := 0.000001
const CAVES := &"crystal_caves"

var _player: PlayerData
var _biomes_data: BiomesData
var _data: EventsData
var _fertilizer: FertilizerSystem
var _system: EventSystem

func before_test() -> void:
	_player = PlayerData.new()
	_biomes_data = BiomesData.new()
	_data = EventsData.new()
	_fertilizer = FertilizerSystem.new(_player, UpgradeSystem.new(), null)

func _currency(type: CurrencyTypes.Types) -> CurrencyDef:
	var def := CurrencyDef.new()
	def.currency_type = type
	def.currency_name = "Test"
	return def

func _boon(id: StringName, type: CurrencyTypes.Types, pct: float, flat: float,
		minimum: float) -> RandomEventDef:
	var def := RandomEventDef.new()
	def.id = id
	def.kind = RandomEventDef.Kind.BOON
	def.currency = _currency(type)
	def.pct_of_balance = pct
	def.flat_amount = flat
	def.min_amount = minimum
	return def

func _fert_boon(id: StringName, low: float, high: float) -> RandomEventDef:
	var def := RandomEventDef.new()
	def.id = id
	def.kind = RandomEventDef.Kind.BOON
	def.fertilizer_min = low
	def.fertilizer_max = high
	return def

func _spend(id: StringName, type: CurrencyTypes.Types, minimum: float,
		reward: float) -> RandomEventDef:
	var def := RandomEventDef.new()
	def.id = id
	def.kind = RandomEventDef.Kind.SPEND
	def.currency = _currency(type)
	def.min_amount = minimum
	def.fertilizer_min = reward
	def.fertilizer_max = reward
	return def

func _progress(id: StringName, goal: int, reward: float) -> RandomEventDef:
	var def := RandomEventDef.new()
	def.id = id
	def.kind = RandomEventDef.Kind.PROGRESS
	def.goal_ticks = goal
	def.fertilizer_min = reward
	def.fertilizer_max = reward
	return def

func _build(defs: Array[RandomEventDef]) -> void:
	var list := RandomEventList.new()
	list.events = defs
	_system = EventSystem.new(_data, _player, _biomes_data, _fertilizer, list)
	_system.rng.seed = 1234

# ---------------------------------------------------------------- spawning

func test_interval_stays_inside_the_authored_window() -> void:
	_build([_boon(&"b", CurrencyTypes.Types.NUTRIENTS, 0.0, 10.0, 10.0)])
	for _i in 200:
		var interval := _system.next_interval()
		assert_bool(interval >= EventSystem.MIN_INTERVAL).is_true()
		assert_bool(interval <= EventSystem.MAX_INTERVAL).is_true()

func test_queue_stops_growing_at_max_queue() -> void:
	_build([_boon(&"b", CurrencyTypes.Types.NUTRIENTS, 0.0, 10.0, 10.0)])
	for _i in EventSystem.MAX_QUEUE:
		assert_bool(_system.try_spawn()).is_true()
	assert_bool(_system.try_spawn()).is_false()
	assert_int(_data.count()).is_equal(EventSystem.MAX_QUEUE)

## Read off the run's own unlocked set, so a locked biome keeps its event out of
## the pool entirely rather than spawning one that cannot pay.
func test_a_biome_gated_event_stays_out_of_the_pool_while_locked() -> void:
	var gated := _boon(&"geode", CurrencyTypes.Types.CRYSTALS, 0.0, 5.0, 5.0)
	gated.requires_biome = CAVES
	_build([gated])
	assert_bool(_system.try_spawn()).is_false()
	assert_int(_data.count()).is_equal(0)
	_biomes_data.unlock(CAVES)
	assert_bool(_system.try_spawn()).is_true()

func test_an_empty_pool_spawns_nothing() -> void:
	_build([] as Array[RandomEventDef])
	assert_bool(_system.try_spawn()).is_false()

# ---------------------------------------------------------------- amounts

func test_amount_uses_the_floor_while_the_balance_is_small() -> void:
	_build([_boon(&"b", CurrencyTypes.Types.NUTRIENTS, 0.05, 100.0, 100.0)])
	_player.nutrients = BigNumber.from_value(0.0)
	assert_float(_system.amount_for(_system.def_for(&"b")).to_float()).is_equal_approx(100.0, EPS)

func test_amount_scales_with_the_balance_once_it_clears_the_floor() -> void:
	_build([_boon(&"b", CurrencyTypes.Types.NUTRIENTS, 0.05, 100.0, 100.0)])
	_player.nutrients = BigNumber.from_value(10000.0)
	assert_float(_system.amount_for(_system.def_for(&"b")).to_float()).is_equal_approx(600.0, EPS)

# ---------------------------------------------------------------- answering

func test_collect_pays_the_boon_and_clears_the_card() -> void:
	_build([_boon(&"b", CurrencyTypes.Types.WATER, 0.0, 25.0, 25.0)])
	_system.try_spawn()
	var instance_id: int = _data.events[0]["instance_id"]
	assert_bool(_system.collect(instance_id)).is_true()
	assert_float(_player.water.to_float()).is_equal_approx(25.0, EPS)
	assert_int(_data.count()).is_equal(0)
	assert_int(_player.events_resolved).is_equal(1)

func test_collect_moves_the_lifetime_total_for_nutrients() -> void:
	_build([_boon(&"b", CurrencyTypes.Types.NUTRIENTS, 0.0, 40.0, 40.0)])
	_system.try_spawn()
	var before := _player.lifetime_nutrients.to_float()
	_system.collect(_data.events[0]["instance_id"])
	assert_float(_player.lifetime_nutrients.to_float()).is_equal_approx(before + 40.0, EPS)

func test_a_fertilizer_boon_pays_its_rolled_amount() -> void:
	_build([_fert_boon(&"windfall", 2.0, 2.0)])
	_system.try_spawn()
	var event: Dictionary = _data.events[0]
	assert_float(_system.reward_for(event).to_float()).is_equal_approx(2.0, EPS)
	_system.collect(event["instance_id"])
	assert_float(_player.fertilizer.to_float()).is_equal_approx(2.0, EPS)
	assert_float(_player.lifetime_fertilizer.to_float()).is_equal_approx(2.0, EPS)

func test_fulfil_charges_the_resource_and_pays_fertilizer() -> void:
	_build([_spend(&"s", CurrencyTypes.Types.WATER, 30.0, 3.0)])
	_player.water = BigNumber.from_value(100.0)
	_system.try_spawn()
	assert_bool(_system.fulfil(_data.events[0]["instance_id"])).is_true()
	assert_float(_player.water.to_float()).is_equal_approx(70.0, EPS)
	assert_float(_player.fertilizer.to_float()).is_equal_approx(3.0, EPS)
	assert_int(_data.count()).is_equal(0)

func test_fulfil_refuses_and_mutates_nothing_when_short() -> void:
	_build([_spend(&"s", CurrencyTypes.Types.WATER, 30.0, 3.0)])
	_player.water = BigNumber.from_value(10.0)
	_system.try_spawn()
	assert_bool(_system.fulfil(_data.events[0]["instance_id"])).is_false()
	assert_float(_player.water.to_float()).is_equal_approx(10.0, EPS)
	assert_float(_player.fertilizer.to_float()).is_equal_approx(0.0, EPS)
	assert_int(_data.count()).is_equal(1)
	assert_int(_player.events_resolved).is_equal(0)

## Dismissing is not answering: the ladder measures offers taken, not offers seen.
func test_skip_clears_the_card_without_paying_or_counting() -> void:
	_build([_boon(&"b", CurrencyTypes.Types.WATER, 0.0, 25.0, 25.0)])
	_system.try_spawn()
	assert_bool(_system.skip(_data.events[0]["instance_id"])).is_true()
	assert_int(_data.count()).is_equal(0)
	assert_float(_player.water.to_float()).is_equal_approx(0.0, EPS)
	assert_int(_player.events_resolved).is_equal(0)

func test_collect_refuses_an_unknown_instance() -> void:
	_build([_boon(&"b", CurrencyTypes.Types.WATER, 0.0, 25.0, 25.0)])
	assert_bool(_system.collect(999)).is_false()

# ---------------------------------------------------------------- progress

func test_a_progress_event_pays_out_exactly_at_its_goal() -> void:
	_build([_progress(&"p", 4, 3.0)])
	_system.try_spawn()
	for _i in 3:
		_system.handle_tick()
		assert_int(_data.count()).is_equal(1)
		assert_float(_player.fertilizer.to_float()).is_equal_approx(0.0, EPS)
	_system.handle_tick()
	assert_int(_data.count()).is_equal(0)
	assert_float(_player.fertilizer.to_float()).is_equal_approx(3.0, EPS)
	assert_int(_player.events_resolved).is_equal(1)

## A tick advances progress quests and leaves everything else alone.
func test_a_tick_does_not_touch_a_boon() -> void:
	_build([_boon(&"b", CurrencyTypes.Types.WATER, 0.0, 25.0, 25.0)])
	_system.try_spawn()
	for _i in 10:
		_system.handle_tick()
	assert_int(_data.count()).is_equal(1)
	assert_int(_data.events[0]["progress"]).is_equal(0)

# ---------------------------------------------------------------- save

func test_the_queue_survives_a_round_trip_with_progress_in_flight() -> void:
	_build([_progress(&"p", 4, 3.0)])
	_system.try_spawn()
	_system.handle_tick()
	_system.handle_tick()
	var restored := EventsData.from_save(_data.to_save())
	assert_int(restored.count()).is_equal(1)
	assert_str(String(restored.events[0]["def_id"])).is_equal("p")
	assert_int(restored.events[0]["progress"]).is_equal(2)
	assert_int(restored.events[0]["roll"]).is_equal(3)

## Never reused, so a card freed while its payout is in flight cannot be matched
## by a later event taking its slot.
func test_instance_ids_do_not_restart_after_a_load() -> void:
	_build([_boon(&"b", CurrencyTypes.Types.WATER, 0.0, 25.0, 25.0)])
	_system.try_spawn()
	var first: int = _data.events[0]["instance_id"]
	var restored := EventsData.from_save(_data.to_save())
	restored.remove(first)
	assert_int(restored.add(&"b", 0)).is_greater(first)

func test_a_corrupt_entry_is_skipped_rather_than_fatal() -> void:
	var restored := EventsData.from_save({"events": ["not a dictionary"]})
	assert_int(restored.count()).is_equal(0)
