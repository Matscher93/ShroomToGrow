class_name MyceliumNode
extends Resource
## Mycelium node definition, tracks the number of manual and automatically bought nodes

signal manual_nodes_changed(value: int)
signal auto_nodes_changed(value: int)


@export var name: String = ""
@export var manual_nodes: int = 0:
	set(value):
		if manual_nodes == value:
			return
		manual_nodes = value
		manual_nodes_changed.emit(manual_nodes)
		
@export var auto_nodes: int = 0:
	set(value):
		if auto_nodes == value:
			return
		auto_nodes = value
		auto_nodes_changed.emit(auto_nodes)
		
@export var initial_cost_mantissa: float = 1.0
@export var initial_cost_exponent: int = 1
