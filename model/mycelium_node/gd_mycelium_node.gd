class_name MyceliumNode
extends Resource

signal manual_nodes_changed(value: int)
signal auto_nodes_changed(value: BigNumber)

## Open batches, and the fields written while they were open. Same idiom, and the
## same rationale, as PlayerData.begin_batch() and UpgradeSystem.begin_batch().
var _batch_depth := 0
var _batch_pending: Dictionary = {}

## Suppresses this run of writes' change signals until the outermost end_batch(),
## which then emits once per field that actually moved, with the value it ended
## on. The fields are written as they happen, so any read in between sees the new
## value - only the notification waits.
##
## What this is for: the offline catch-up moves auto_nodes on every tier every
## tick, and each write costs the bound node card seven property_changed
## notifications and the formatted label strings behind them.
##
## Always pair with end_batch(). Nesting is counted, only the outermost emits.
func begin_batch() -> void:
	_batch_depth += 1

func end_batch() -> void:
	_batch_depth = maxi(0, _batch_depth - 1)
	if _batch_depth > 0 or _batch_pending.is_empty():
		return
	var pending := _batch_pending.keys()
	_batch_pending.clear()
	for field: StringName in pending:
		emit_signal("%s_changed" % field, get(field))

func _defer(field: StringName) -> bool:
	if _batch_depth <= 0:
		return false
	_batch_pending[field] = true
	return true

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
		if _defer(&"manual_nodes"): return
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
		if _defer(&"auto_nodes"): return
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
# Buy cost: initial_cost * cost_increase_per_level^(manual_nodes * cost_growth_exponent^manual_nodes).
@export var cost_growth_exponent: float = 1.2  # >1 steepens the buy-cost curve with manual_nodes

func has_nodes() -> bool:
	return manual_nodes > 0 or auto_nodes.gt(BigNumber.from_value(0.0))
