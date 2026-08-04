class_name TickSystem
extends RefCounted
## MODEL: the per-tick production cascade.
##
## Each node tier's output feeds the tier below it, and tier 0 feeds nutrients.
## Holds only its inputs, no App reference, so it can be built and exercised in
## isolation.

var _nodes: Array[MyceliumNode]
var _player_data: PlayerData
var _production: ProductionSystem

func _init(nodes: Array[MyceliumNode], player_data: PlayerData,
		production: ProductionSystem) -> void:
	_nodes = nodes
	_player_data = player_data
	_production = production

## Per-node production multiplier, indexed like the node array. Callers driving
## many ticks back-to-back (offline catch-up) compute this once and pass it into
## handle_tick(): node_production_bonus() is a chain of ~9 UpgradeSystem.modify()
## calls, and redoing it per node per tick dominates a long catch-up loop. Safe
## to hoist because its only live inputs are upgrade levels and manual node
## counts, and every ScalingSourceDef kind is player-action driven (see
## ResolveContext), so nothing goes stale mid-loop.
func node_production_bonuses() -> Array[BigNumber]:
	var bonuses: Array[BigNumber] = []
	for node in _nodes:
		bonuses.append(_production.node_production_bonus(StringName(str(node.node_id))))
	return bonuses

## Advances the game one tick. Pass `bonuses` to reuse a hoisted set, leave it
## empty to compute them fresh.
func handle_tick(bonuses: Array[BigNumber] = []) -> void:
	_player_data.tick_count += 1
	_player_data.lifetime_ticks += 1
	if bonuses.is_empty():
		bonuses = node_production_bonuses()
	# Highest tier first, and that order is load-bearing: each tier writes into
	# the tier below *before* that tier produces, so a top-tier gain reaches
	# nutrients within the same tick. Iterating upwards instead would park each
	# tier's output for the next tick, stretching the payout of an N-tier chain
	# over N ticks and flattening the whole idle curve.
	for i in range(_nodes.size() - 1, -1, -1):
		var node := _nodes[i]
		var node_change := node.auto_nodes.add(BigNumber.from_value(node.manual_nodes))
		node_change = node_change.mul(bonuses[i])
		if i != 0:
			var receiving_node := _nodes[i - 1]
			receiving_node.auto_nodes = receiving_node.auto_nodes.add(node_change)
		else:
			_player_data.nutrients = _player_data.nutrients.add(node_change)
			_player_data.lifetime_nutrients = _player_data.lifetime_nutrients.add(node_change)
