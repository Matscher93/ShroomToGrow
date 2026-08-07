class_name MyceliumNode
extends Resource

signal manual_nodes_changed(value: int)
signal auto_nodes_changed(value: BigNumber)

@export var node_id: int = 0
@export var name: String = ""

## node_id as the StringName every NODE-scoped upgrade effect is keyed by.
##
## Cached rather than rebuilt per read: the tick loop asks once per node per
## tick and the bound ViewModels ask ~6 times per repaint, and each rebuild is a
## String allocation plus a StringName intern for a value that never changes.
var _id_key_cache: StringName = &""
var id_key: StringName:
	get:
		if _id_key_cache.is_empty():
			_id_key_cache = StringName(str(node_id))
		return _id_key_cache
@export var desc: String = ""
@export var manual_nodes: int = 0:
	set(value):
		if manual_nodes == value:
			return
		manual_nodes = value
		manual_nodes_changed.emit(manual_nodes)

# BigNumber can't be @export'ed, so the persisted value lives in two plain
# fields. The BigNumber is cached lazily (first read, after .tres load) instead
# of rebuilt per read: the tick loop and bound ViewModels read auto_nodes many
# times per tick, and an allocating getter dominated offline catch-up.
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

## Perk required before this tier can be bought. Empty means available on a
## fresh save (the first three). The perk carries no effect, its purchased
## level *is* the unlock.
@export var unlock_perk_id: StringName = &""

@export var color: Color
@export var level_font_color: Color
@export var cost_increase_per_level: float = 1.5
@export var cost_growth_exponent: float = 1.2  # >1 steepens the buy-cost curve with manual_nodes

func has_nodes() -> bool:
	return manual_nodes > 0 or auto_nodes.gt(BigNumber.from_value(0.0))
