class_name MyceliumNodeData
extends RefCounted
## MODEL — one node tier's live state plus its purchase rules.

signal node_changed(nodes: MyceliumNode)

var _player_data: PlayerData

## The node resource this tier wraps. Public: App, SaveManager, the ViewModels
## and the offline-income view all legitimately read it, and they were reaching
## through a `_node` that only looked private.
var node: MyceliumNode:
	set(value):
		if node == value:
			return
		node = value
		node_changed.emit(node)

func _init(player_data: PlayerData, in_node: MyceliumNode) -> void:
	_player_data = player_data
	node = in_node

## Game rules live here (or in dedicated systems that mutate the model).
func upgrade_cost() -> BigNumber:
	var scaled_level := pow(float(node.manual_nodes), node.cost_growth_exponent)
	return node.initial_cost.mul(BigNumber.from_value(node.cost_increase_per_level).pow_float(scaled_level))

func can_afford_upgrade() -> bool:
	return _player_data.nutrients.gte(upgrade_cost())

func buy_upgrade() -> bool:
	if not can_afford_upgrade():
		return false
	_player_data.nutrients = _player_data.nutrients.sub(upgrade_cost())
	node.manual_nodes += 1
	return true
