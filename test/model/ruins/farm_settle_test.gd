extends GdUnitTestSuite
## Unit tests for the farms - MissionSystem.settle_farms() and the two boards.
##
## Built against a hand-authored list rather than the shipped data, and driven
## entirely through the injected clock: a farm cycle is a statement about two
## timestamps, which is the one thing a test cannot wait out.
##
## What is being asserted throughout is that the sweep is *arithmetic*, not a
## replay. Whole cycles are divided out of the elapsed seconds, so settling a
## farm left running overnight costs exactly what settling one left for a second
## does - and forfeits everything past the 24h cap rather than banking it for the
## next sweep to find.

const EPS := 0.000001

## One cycle of the fixture's farm, in seconds.
const CYCLE := 100.0
## What one cycle pays.
const PER_CYCLE := 10.0

var _player: PlayerData
var _biomes_data: BiomesData
var _prestige: UpgradeSystem
var _upgrades: UpgradeSystem
var _production: ProductionSystem
var _ctx: ResolveContext
var _data: RuinsData
var _heroes: HeroSystem
var _system: MissionSystem
var _workers: WorkerSystem
var _now: float = 1000.0

func before_test() -> void:
	_now = 1000.0
	_player = PlayerData.new()
	_player.relics = BigNumber.from_value(0.0)
	_biomes_data = BiomesData.new()
	_biomes_data.unlock(MissionSystem.RUINS_KEY)
	_prestige = UpgradeSystem.new()
	_upgrades = UpgradeSystem.new()
	_ctx = ResolveContext.new()
	_production = ProductionSystem.new(UpgradeSystem.new(), UpgradeSystem.new(),
		_prestige, _ctx, UpgradeSystem.new(), UpgradeSystem.new(), UpgradeSystem.new(),
		UpgradeSystem.new(), _upgrades)
	_data = RuinsData.new()
	_heroes = HeroSystem.new(_data, _player, _hero_list(), _production)
	_workers = WorkerSystem.new(_data, _player, _worker_cost(), _production)
	_system = MissionSystem.new(_data, _player, _biomes_data, _production, _heroes,
		_mission_list(), _prestige, null, _workers)
	# Enough hired that the tests below are about the farms rather than about
	# being able to staff one.
	_data.workers_owned = 6
	_system.now_provider = func() -> float: return _now
	_heroes.recruit(&"digger")
	_heroes.recruit(&"hauler")

# ─── Fixtures ────────────────────────────────────────────────────────────────

func _payout(mantissa: float, exponent: int) -> MissionPayoutDef:
	var currency := CurrencyDef.new()
	currency.currency_type = CurrencyTypes.Types.RELICS
	currency.currency_name = "Test"
	var payout := MissionPayoutDef.new()
	payout.currency = currency
	payout.gain_stat = &"relic_gain"
	payout.amount = BigNumber.new(mantissa, exponent)
	return payout

func _mission_list() -> MissionList:
	var errand := MissionDef.new()
	errand.id = &"errand"
	errand.hero_id = &"digger"
	errand.display_name = "Errand"
	errand.base_duration_seconds = 100.0
	errand.min_hero_level = 1
	errand.payouts = [_payout(1.0, 0)]

	var plot := MissionDef.new()
	plot.id = &"plot"
	plot.display_name = "Plot"
	plot.is_farm = true
	plot.base_duration_seconds = CYCLE
	plot.min_hero_level = 1
	plot.payouts = [_payout(1.0, 1)]

	var list := MissionList.new()
	list.missions = [errand, plot]
	return list

func _hero_list() -> HeroList:
	var list := HeroList.new()
	list.heroes = [_hero(&"digger", "Digger"), _hero(&"hauler", "Hauler")]
	return list

func _hero(id: StringName, name: String) -> HeroDef:
	var currency := CurrencyDef.new()
	currency.currency_type = CurrencyTypes.Types.RELICS
	var def := HeroDef.new()
	def.id = id
	def.display_name = name
	def.speed_per_level = 0.0     # level 1 is a clean x1.0, so cycles read as authored
	def.yield_per_level = 0.0
	def.base_level_cap = 5
	def.recruit_currency = currency
	def.recruit_cost = BigNumber.new(0.0, 0)
	def.level_currency = currency
	def.level_base_cost = BigNumber.new(0.0, 0)
	def.level_cost_growth = 1.0
	return def

func _relics() -> float:
	return _player.relics.to_float()

func _worker_cost() -> WorkerCostDef:
	var currency := CurrencyDef.new()
	currency.currency_type = CurrencyTypes.Types.RELICS
	var price := MissionPayoutDef.new()
	price.currency = currency
	price.amount = BigNumber.new(1.0, 1)      # 10 relics, doubling per worker
	var cost := WorkerCostDef.new()
	cost.prices = [price] as Array[MissionPayoutDef]
	cost.cost_growth = 2.0
	return cost

## Raises how many workers one farm will hold, the way a boost rung does.
func _grant_worker_room(levels: int) -> void:
	var effect := UpgradeEffectDef.new()
	effect.stat = &"workers_per_farm"
	effect.op = UpgradeEffectDef.Op.ADD
	effect.per_level = 1.0
	var def := UpgradeDef.new()
	def.id = &"room"
	def.max_level = levels
	def.effects = [effect] as Array[UpgradeEffectDef]
	_upgrades.register(def)
	for _i in levels:
		assert_bool(_upgrades.buy_with_points(&"room", true)).is_true()

func _start_farm(workers: int = 1) -> int:
	var instance_id := _system.start_farm(&"plot", workers)
	assert_int(instance_id).is_greater(0)
	return instance_id

# ─── The sweep ───────────────────────────────────────────────────────────────

func test_a_farm_pays_nothing_before_its_first_cycle_is_whole() -> void:
	_start_farm()
	_now += CYCLE - 1.0
	assert_int(_system.settle_farms()).is_zero()
	assert_float(_relics()).is_equal_approx(0.0, EPS)

func test_a_whole_cycle_pays_once() -> void:
	_start_farm()
	_now += CYCLE
	assert_int(_system.settle_farms()).is_equal(1)
	assert_float(_relics()).is_equal_approx(PER_CYCLE, EPS)

func test_many_cycles_pay_in_one_sweep() -> void:
	_start_farm()
	_now += CYCLE * 12.0
	assert_int(_system.settle_farms()).is_equal(12)
	assert_float(_relics()).is_equal_approx(PER_CYCLE * 12.0, EPS)

## The part-cycle in progress is kept, not rounded away. Without this a farm
## swept every tick would lose the remainder each time and never pay at all.
func test_the_part_cycle_in_progress_is_not_lost() -> void:
	_start_farm()
	_now += CYCLE * 2.0 + 50.0
	assert_int(_system.settle_farms()).is_equal(2)
	# 50s of the third cycle were already served, so 50 more finish it.
	_now += 50.0
	assert_int(_system.settle_farms()).is_equal(1)
	assert_float(_relics()).is_equal_approx(PER_CYCLE * 3.0, EPS)

func test_sweeping_twice_in_the_same_second_pays_once() -> void:
	_start_farm()
	_now += CYCLE * 3.0
	assert_int(_system.settle_farms()).is_equal(3)
	assert_int(_system.settle_farms()).is_zero()
	assert_float(_relics()).is_equal_approx(PER_CYCLE * 3.0, EPS)

func test_a_farm_moves_the_tally_by_the_cycles_it_paid() -> void:
	_start_farm()
	_now += CYCLE * 7.0
	_system.settle_farms()
	assert_int(_data.missions_completed).is_equal(7)
	assert_int(_player.missions_completed).is_equal(7)

# ─── The offline cap ─────────────────────────────────────────────────────────

func test_a_long_gap_pays_only_up_to_the_cap() -> void:
	_start_farm()
	_now += OfflineProgress.MAX_SECONDS * 2.0
	var capped_cycles := int(OfflineProgress.MAX_SECONDS / CYCLE)
	assert_int(_system.settle_farms()).is_equal(capped_cycles)

## The half of the cap that matters: time past it is forfeited, not banked. An
## implementation that advanced started_at by the cycles paid would leave the
## start still behind the cap, and this second sweep would hand back everything
## the first one just refused.
func test_time_past_the_cap_is_not_paid_on_the_next_sweep() -> void:
	_start_farm()
	_now += OfflineProgress.MAX_SECONDS * 2.0
	_system.settle_farms()
	var banked := _relics()
	assert_int(_system.settle_farms()).is_zero()
	assert_float(_relics()).is_equal_approx(banked, EPS)

# ─── The two boards ──────────────────────────────────────────────────────────

## The farms are the only capped board, so a farm must not count against the
## expeditions - and, more to the point, must not eat the plot cap for nothing.
func test_a_farm_is_not_counted_as_an_expedition() -> void:
	_start_farm()
	assert_int(_system.expeditions_out()).is_zero()
	assert_int(_system.farm_slots_used()).is_equal(1)

func test_an_expedition_does_not_take_a_farm_plot() -> void:
	assert_int(_system.send(&"errand", &"digger")).is_greater(0)
	assert_int(_system.farm_slots_used()).is_zero()
	assert_int(_system.expeditions_out()).is_equal(1)
	assert_bool(_system.has_free_farm_slot()).is_true()

## The two halves of the roster never compete: a farm is worked by workers, so
## starting one leaves every hero free for its own chain.
func test_a_farm_leaves_the_heroes_alone() -> void:
	_start_farm()
	assert_bool(_heroes.is_busy(&"digger")).is_false()
	assert_bool(_system.can_send(&"errand", &"digger")).is_true()

func test_the_farm_board_fills_up() -> void:
	_start_farm()
	assert_bool(_system.has_free_farm_slot()).is_false()
	assert_int(_system.start_farm(&"plot", 1)).is_zero()

func test_send_refuses_a_farm_and_start_farm_refuses_an_expedition() -> void:
	assert_int(_system.send(&"plot", &"digger")).is_zero()
	assert_int(_system.start_farm(&"errand", 1)).is_zero()

# ─── Collecting ──────────────────────────────────────────────────────────────

## A farm is never waiting on a press - settle_farms() has already paid it - so
## it must not raise the badge or arm the Collect all button.
func test_a_farm_is_never_collectable() -> void:
	_start_farm()
	_now += CYCLE * 3.0
	assert_int(_system.completed_count()).is_zero()
	assert_bool(_system.has_collectable()).is_false()

func test_collect_refuses_a_farm() -> void:
	var instance_id := _start_farm()
	_now += CYCLE * 3.0
	assert_bool(_system.collect(instance_id)).is_false()
	assert_int(_data.count()).is_equal(1)

func test_collect_all_leaves_the_farms_running() -> void:
	_start_farm()
	assert_int(_system.send(&"errand", &"digger")).is_greater(0)
	_now += CYCLE * 2.0
	assert_int(_system.collect_all()).is_equal(1)
	assert_int(_system.farm_slots_used()).is_equal(1)

# ─── Stopping ────────────────────────────────────────────────────────────────

## Stopping settles first, so taking a hero off never costs the player a
## cycle it had already turned.
func test_stopping_a_farm_pays_what_it_had_earned() -> void:
	var instance_id := _start_farm()
	_now += CYCLE * 2.0 + 30.0
	assert_bool(_system.stop_farm(instance_id)).is_true()
	assert_float(_relics()).is_equal_approx(PER_CYCLE * 2.0, EPS)
	assert_int(_system.farm_slots_used()).is_zero()
	# The workers are back in the pool the moment the entry is gone: where a
	# worker is, is read off the board.
	assert_int(_workers.idle()).is_equal(6)

func test_stop_farm_refuses_an_expedition() -> void:
	var instance_id := _system.send(&"errand", &"digger")
	assert_bool(_system.stop_farm(instance_id)).is_false()
	assert_int(_data.count()).is_equal(1)

# ─── The bar ─────────────────────────────────────────────────────────────────

## A farm's bar wraps rather than filling and stopping, because the farm does.
func test_farm_progress_wraps_through_each_cycle() -> void:
	_start_farm()
	var entry := _data.active[0]
	assert_float(_system.farm_progress_ratio(entry)).is_equal_approx(0.0, EPS)
	_now += CYCLE * 0.25
	assert_float(_system.farm_progress_ratio(entry)).is_equal_approx(0.25, EPS)
	_now += CYCLE
	assert_float(_system.farm_progress_ratio(entry)).is_equal_approx(0.25, EPS)

# ─── Save ────────────────────────────────────────────────────────────────────

func test_a_farm_survives_a_save_round_trip_as_a_farm() -> void:
	_start_farm()
	var restored := RuinsData.from_save(_data.to_save())
	assert_int(restored.count()).is_equal(1)
	assert_bool(bool(restored.active[0]["is_farm"])).is_true()

## A save written before farms existed holds expeditions only, and every entry in
## it has to load as one.
func test_an_entry_saved_without_a_kind_loads_as_an_expedition() -> void:
	var old_save := {
		"active": [{
			"mission_id": "errand",
			"hero_id": "digger",
			"started_at": 500.0,
			"duration": 100.0,
			"instance_id": 3,
			"payouts": [],
		}],
		"missions_completed": 4,
	}
	var restored := RuinsData.from_save(old_save)
	assert_int(restored.count()).is_equal(1)
	assert_bool(bool(restored.active[0]["is_farm"])).is_false()
	assert_int(restored.missions_completed).is_equal(4)

# ─── Workers ─────────────────────────────────────────────────────────────────

## The whole point of a second worker: N of them divide the cycle by N.
func test_workers_divide_the_cycle() -> void:
	assert_float(_system.duration_for(&"plot", &"", 1)).is_equal_approx(CYCLE, EPS)
	assert_float(_system.duration_for(&"plot", &"", 2)).is_equal_approx(CYCLE / 2.0, EPS)
	assert_float(_system.duration_for(&"plot", &"", 4)).is_equal_approx(CYCLE / 4.0, EPS)

## A farm holds one worker until an upgrade says otherwise, so a second is
## refused before the ceiling moves and taken after it.
func test_a_farm_holds_one_worker_until_the_ceiling_moves() -> void:
	assert_int(_workers.max_per_farm(&"plot")).is_equal(WorkerSystem.BASE_WORKERS_PER_FARM)
	assert_int(_system.start_farm(&"plot", 2)).is_zero()
	_grant_worker_room(2)
	assert_int(_workers.max_per_farm(&"plot")).is_equal(3)
	assert_int(_system.start_farm(&"plot", 2)).is_greater(0)

func test_a_farm_cannot_take_more_workers_than_are_idle() -> void:
	_grant_worker_room(9)
	_data.workers_owned = 2
	assert_int(_system.start_farm(&"plot", 3)).is_zero()
	assert_int(_system.start_farm(&"plot", 2)).is_greater(0)
	assert_int(_workers.idle()).is_zero()

## Adding a worker settles first, so the cycles already turned are paid at the
## rate they were turned at rather than at the new one.
func test_adding_a_worker_settles_before_it_speeds_the_farm_up() -> void:
	_grant_worker_room(3)
	var instance_id := _start_farm()
	_now += CYCLE * 2.0
	assert_bool(_system.set_farm_workers(instance_id, 2)).is_true()
	assert_float(_relics()).is_equal_approx(PER_CYCLE * 2.0, EPS)
	assert_float(float(_data.find(instance_id)["duration"])).is_equal_approx(CYCLE / 2.0, EPS)

	# And from here it pays at the new rate: half a cycle is now CYCLE/2.
	_now += CYCLE / 2.0
	assert_int(_system.settle_farms()).is_equal(1)
	assert_float(_relics()).is_equal_approx(PER_CYCLE * 3.0, EPS)

## The part-cycle already served is carried as a share of the cycle rather than
## as seconds, so a worker added halfway through leaves the farm halfway through.
func test_a_part_cycle_is_carried_across_a_worker_change() -> void:
	_grant_worker_room(3)
	var instance_id := _start_farm()
	_now += CYCLE / 2.0
	_system.set_farm_workers(instance_id, 2)
	assert_float(_system.farm_progress_ratio(_data.find(instance_id))).is_equal_approx(0.5, EPS)

func test_a_worker_change_below_one_or_above_the_ceiling_is_refused() -> void:
	var instance_id := _start_farm()
	assert_bool(_system.set_farm_workers(instance_id, 0)).is_false()
	assert_bool(_system.set_farm_workers(instance_id, 2)).is_false()
	assert_int(int(_data.find(instance_id)["workers"])).is_equal(1)

func test_workers_on_a_farm_are_not_idle() -> void:
	_grant_worker_room(3)
	_start_farm(3)
	assert_int(_workers.assigned()).is_equal(3)
	assert_int(_workers.idle()).is_equal(3)

## A farm pays its authored rate per cycle however many workers turn it: they are
## already paid for in cycles, and paying them twice would make stacking one farm
## strictly better than running two.
func test_workers_speed_the_farm_without_also_enriching_it() -> void:
	_grant_worker_room(3)
	_start_farm(2)
	_now += CYCLE
	assert_int(_system.settle_farms()).is_equal(2)
	assert_float(_relics()).is_equal_approx(PER_CYCLE * 2.0, EPS)
