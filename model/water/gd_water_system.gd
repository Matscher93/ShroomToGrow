class_name WaterSystem
extends RefCounted
## MODEL: the well's pump - how often the Underground Lake yields water and how
## much one yield is worth.
##
## Holds only its inputs, no App reference, so it can be built and exercised in
## isolation.
##
## Water is deliberately outside TickSystem's production cascade: nothing feeds
## it from the mycelium tiers, so it is not part of the linear jump kernel and
## the tier arithmetic there stays untouched. What it does share with that
## cascade is the requirement to land on the same total whether a span is walked
## one tick at a time (the live timer, the offline catch-up) or strided in one
## step (the balance simulator) - see handle_ticks().

## Ticks between pumps before any &"water_rate" effect shortens the gap.
const BASE_INTERVAL := 10.0

## Floor on that gap, so a stacked discount can never reach zero and pump every
## tick for free. Mirrors App.MIN_TICK_DURATION.
const MIN_INTERVAL := 1.0

## Water one pump draws up before any &"water_production" multiplier.
const BASE_YIELD := 1.0

## The biome whose unlock opens the well. Its screen is the Well.
const LAKE_KEY := &"underground_lake"

var _player_data: PlayerData
var _biomes_data: BiomesData
var _production: ProductionSystem

func _init(player_data: PlayerData, biomes_data: BiomesData,
		production: ProductionSystem) -> void:
	_player_data = player_data
	_biomes_data = biomes_data
	_production = production

# ---------------------------------------------------------------- rates

## Read off the run's own unlocked set rather than is_ever_unlocked, matching
## water itself being wiped by the sporation: a run that has not bought the lake
## back pumps nothing, however many times an earlier run reached it.
func is_pumping() -> bool:
	return _biomes_data.is_unlocked(LAKE_KEY)

## Whole ticks between pumps. Rounded rather than floored so a half-tick of
## discount is worth something rather than nothing.
func interval() -> int:
	return maxi(1, int(round(_production.water_interval(BASE_INTERVAL, MIN_INTERVAL))))

func pump_yield() -> BigNumber:
	return _production.modify_water_gain(BigNumber.from_value(BASE_YIELD))

## The pump's rate as one hoistable value, for a caller advancing many ticks in a
## row. See WaterPumpPlan for what makes it safe to reuse.
## A stopped pump short-circuits rather than resolving a rate nothing will use,
## keeping this no dearer than the is_pumping() check handle_ticks() used to open
## with.
func pump_plan() -> WaterPumpPlan:
	if not is_pumping():
		return WaterPumpPlan.new(false, int(MIN_INTERVAL), BigNumber.new(0.0, 0))
	return WaterPumpPlan.new(true, interval(), pump_yield())

## Ticks the player still waits for the next pump, for the Well's status line.
## Reports a full interval while the pump is stopped, since that is what the wait
## would be if the lake reopened now.
func ticks_until_pump(tick_count: int) -> int:
	var every := interval()
	return every - tick_count % every

# ---------------------------------------------------------------- pumping

## Pays out every pump that falls in the `count` ticks following
## `tick_count_before`, which is the tick counter as it stood before the span was
## advanced.
##
## Counted as a difference of two divisions rather than tested with a modulo,
## because TickSystem.advance_by() moves the counter by more than one and a
## modulo would step straight over the exact multiples inside the span. This is
## what makes a strided span pay exactly what walking it tick by tick would.
##
## Pass `plan` to reuse a hoisted rate, leave it null to read one fresh. Both
## paths pay the same water - the plan holds exactly what the fresh path would
## compute - so only the cost differs.
func handle_ticks(tick_count_before: int, count: int, plan: WaterPumpPlan = null) -> void:
	if count <= 0: return
	if plan == null:
		plan = pump_plan()
	if not plan.pumping: return
	var every := plan.interval
	@warning_ignore("integer_division")
	var events := (tick_count_before + count) / every - tick_count_before / every
	if events <= 0: return
	_player_data.water = _player_data.water.add(plan.yield_per_pump.scale(float(events)))
