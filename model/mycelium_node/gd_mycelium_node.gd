class_name MyceliumNode
extends Resource

signal manual_nodes_changed(value: int)
signal auto_nodes_changed(value: BigNumber)

@export var node_id: int = 0
@export var name: String = ""
@export var desc: String = ""
@export var manual_nodes: int = 0:
	set(value):
		if manual_nodes == value:
			return
		manual_nodes = value
		manual_nodes_changed.emit(manual_nodes)

# BigNumber can't be @export'ed, so the authored/persisted value lives in these
# two plain fields. The BigNumber itself is cached rather than rebuilt on every
# read: auto_nodes is read several times per node per tick by the tick loop and
# the bound ViewModels, and a getter that allocates made that the hottest
# allocation site in the offline catch-up loop. The cache is built lazily on
# first read so a .tres deserialising straight into the backing fields is picked
# up correctly, and BigNumber arithmetic always returns new instances, so
# holding this reference can't be invalidated from the outside.
@export var _auto_nodes_mantissa: float = 0.0
@export var _auto_nodes_exponent: int = 1
var _auto_nodes_cache: BigNumber
var auto_nodes: BigNumber:
	get:
		if _auto_nodes_cache == null:
			_auto_nodes_cache = BigNumber.new(_auto_nodes_mantissa, _auto_nodes_exponent)
		return _auto_nodes_cache
	set(value):
		if value == null or auto_nodes.same_value(value):
			return
		_auto_nodes_cache = value
		_auto_nodes_mantissa = value.mantissa
		_auto_nodes_exponent = value.exponent
		auto_nodes_changed.emit(value)

@export var _initial_cost_mantissa: float = 1.0
@export var _initial_cost_exponent: int = 1
var _initial_cost_cache: BigNumber
var initial_cost: BigNumber:
	get:
		if _initial_cost_cache == null:
			_initial_cost_cache = BigNumber.new(_initial_cost_mantissa, _initial_cost_exponent)
		return _initial_cost_cache
	set(value):
		if value == null:
			return
		_initial_cost_cache = value
		_initial_cost_mantissa = value.mantissa
		_initial_cost_exponent = value.exponent

## Perk that has to be owned before this tier can be bought at all. Empty means
## the tier is available from a fresh save (the first three). Mirrors BiomeDef
## keeping its own unlock requirement as data on the resource — the perk itself
## carries no effect, its purchased level *is* the unlock.
@export var unlock_perk_id: StringName = &""

@export var color: Color
@export var level_font_color: Color
@export var cost_increase_per_level: float = 1.5
@export var cost_growth_exponent: float = 1.2  # >1 makes the buy-cost curve steepen with manual_nodes

func has_nodes() -> bool:
	return manual_nodes > 0 or auto_nodes.gt(BigNumber.from_value(0.0))
