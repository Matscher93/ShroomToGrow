class_name WaterPumpPlan
extends RefCounted
## MODEL: the well's pump rate, hoisted out of a run of ticks.
##
## Same trick, and the same guarantee, as TickSystem.node_production_bonuses():
## both numbers here come from upgrade levels and biome unlocks, so they cannot
## move while nothing is bought. A caller driving many ticks back to back - the
## offline catch-up - builds one of these once instead of paying two
## UpgradeSystem modify chains per tick, every tick, whether or not a pump
## actually lands in it.
##
## Build it with WaterSystem.pump_plan(). Valid until something is bought.

## Whether the lake is open at all this run. False makes handle_ticks() a no-op,
## so a stopped pump costs nothing per tick either.
var pumping: bool

## Whole ticks between pumps.
var interval: int

## Water one pump draws up, after every multiplier.
var yield_per_pump: BigNumber

func _init(in_pumping: bool, in_interval: int, in_yield_per_pump: BigNumber) -> void:
	pumping = in_pumping
	interval = in_interval
	yield_per_pump = in_yield_per_pump
