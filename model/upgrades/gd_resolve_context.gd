class_name ResolveContext
extends RefCounted

var node_counts: Dictionary = {}      # tier -> total
var manual_counts: Dictionary = {}    # tier -> hand-bought   (track this separately in NodeManager)
var resources: Dictionary = {}        # resource -> current amount
var stat_snapshot: Dictionary = {}    # stat -> LAST tick's resolved value  ← the cycle-breaker
var biome_sizes: Dictionary = {}      # biome key -> purchased size

func node_count(tier: StringName, manual_only: bool) -> float:
	return float((manual_counts if manual_only else node_counts).get(tier, 0))

func biome_size(key: StringName) -> float:
	return float(biome_sizes.get(key, 0))

func stat_value(stat: StringName) -> float:
	return stat_snapshot.get(stat, 0.0)

func resource_amount(res: StringName) -> float:
	return resources.get(res, 0.0)
