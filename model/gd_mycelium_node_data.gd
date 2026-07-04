class_name PlayerData
extends RefCounted
## MODEL — pure state and game rules. Knows nothing about ViewModels or UI.
## Swap `float` for your BigNumber class where needed; the pattern is identical
## as long as BigNumber comparisons/emits go through the setters.

signal nutrients_changed(value: BigNumber)
signal nodes_changed(nodes: Array[MyceliumNode])

var nutrients: BigNumber = BigNumber.new(1, 0):
	set(value):
		if nutrients == value:
			return
		nutrients = value
		nutrients_changed.emit(nutrients)
		
var nodes: Array[MyceliumNode]:
	set(value):
		if nodes == value:
			return
		nodes = value
		nodes_changed.emit(nodes)

## Game rules live here (or in dedicated systems that mutate the model).
func upgrade_cost(node_level: int) -> BigNumber:
	var initial_cost = BigNumber.new(nodes[node_level].initial_cost_mantissa, nodes[node_level].initial_cost_exponent)
	return initial_cost.mul(BigNumber.from_value(1.5).pow_int(nodes[node_level].manual_nodes))

func can_afford_upgrade(node_level: int) -> bool:
	return nutrients.gte(upgrade_cost(node_level))

func buy_upgrade(node_level: int) -> bool:
	if not can_afford_upgrade(node_level):
		return false
	nutrients = nutrients.sub(upgrade_cost(node_level))
	nodes[node_level].manual_nodes += 1
	return true
