class_name MyceliumData
extends RefCounted

signal node_changed(nodes: MyceliumNode)

var _player_data: PlayerData
var _node: MyceliumNode:
	set(value):
		if _node == value:
			return
		_node = value
		node_changed.emit(_node)

func _init(player_data: PlayerData, node: MyceliumNode) -> void:
	_player_data = player_data
	_node = node

## Game rules live here (or in dedicated systems that mutate the model).
func upgrade_cost() -> BigNumber:
	return _node.initial_cost.mul(BigNumber.from_value(_node.cost_increase_per_level).pow_int(_node.manual_nodes))

func can_afford_upgrade() -> bool:
	return _player_data.nutrients.gte(upgrade_cost())

func buy_upgrade() -> bool:
	if not can_afford_upgrade():
		return false
	_player_data.nutrients = _player_data.nutrients.sub(upgrade_cost())
	_node.manual_nodes += 1
	return true
	
