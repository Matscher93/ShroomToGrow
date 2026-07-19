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
		
@export var _auto_nodes_mantissa: float = 0.0
@export var _auto_nodes_exponent: int = 1
var auto_nodes: BigNumber:
	get: return BigNumber.new(_auto_nodes_mantissa,_auto_nodes_exponent)
	set(value):
		if auto_nodes == value:
			return
		_auto_nodes_mantissa = value.mantissa
		_auto_nodes_exponent = value.exponent
		auto_nodes_changed.emit(auto_nodes)
		
@export var _initial_cost_mantissa: float = 1.0
@export var _initial_cost_exponent: int = 1
var initial_cost: BigNumber:
	get: return BigNumber.new(_initial_cost_mantissa, _initial_cost_exponent)
	set(value):
		_initial_cost_mantissa = value.mantissa
		_initial_cost_exponent = value.exponent
		
@export var color: Color
@export var level_font_color: Color
@export var cost_increase_per_level: float = 1.5
@export var cost_growth_exponent: float = 1.2  # >1 makes the buy-cost curve steepen with manual_nodes

func has_nodes() -> bool:
	return manual_nodes > 0 or auto_nodes.gt(BigNumber.from_value(0.0))
