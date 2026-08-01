class_name MyceliumNodeData
extends RefCounted
## MODEL — one node tier's live state plus its purchase rules.

signal node_changed(nodes: MyceliumNode)

var _player_data: PlayerData
var _prestige_upgrades: UpgradeSystem

## The node resource this tier wraps. Public: App, SaveManager, the ViewModels
## and the offline-income view all legitimately read it, and they were reaching
## through a `_node` that only looked private.
var node: MyceliumNode:
	set(value):
		if node == value:
			return
		node = value
		node_changed.emit(node)

func _init(player_data: PlayerData, in_node: MyceliumNode, prestige_upgrades: UpgradeSystem) -> void:
	_player_data = player_data
	_prestige_upgrades = prestige_upgrades
	node = in_node

## Game rules live here (or in dedicated systems that mutate the model).
func upgrade_cost() -> BigNumber:
	var scaled_level := pow(float(node.manual_nodes), node.cost_growth_exponent)
	return node.initial_cost.mul(BigNumber.from_value(node.cost_increase_per_level).pow_float(scaled_level))

## The higher tiers stay locked until their unlock perk is bought. Perks survive
## prestige, so a tier unlocked once stays unlocked; nodes already owned in it
## are never taken away, only further purchases are blocked.
func is_unlocked() -> bool:
	if node.unlock_perk_id.is_empty():
		return true
	return _prestige_upgrades.level(node.unlock_perk_id) > 0

func can_afford_upgrade() -> bool:
	return _player_data.nutrients.gte(upgrade_cost())

func can_buy_upgrade() -> bool:
	return is_unlocked() and can_afford_upgrade()

func buy_upgrade() -> bool:
	if not can_buy_upgrade():
		return false
	_player_data.nutrients = _player_data.nutrients.sub(upgrade_cost())
	node.manual_nodes += 1
	return true
