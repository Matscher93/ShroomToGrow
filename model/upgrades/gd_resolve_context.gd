class_name ResolveContext
extends RefCounted
## MODEL: the live inputs a ScalingSourceDef can scale an upgrade effect by.
##
## Everything here must be *player-action driven*, not per-tick: UpgradeSystem
## caches these and only rebuilds on invalidate(), so a per-tick value would
## read stale. Whoever writes a field also invalidates the affected systems (see
## App._track_manual_count and App.buy_biome_size).

var manual_counts: Dictionary = {}    # node tier -> hand-bought count
var biome_sizes: Dictionary = {}      # biome key -> purchased size

## Hand-bought nodes only. Auto-generated nodes deliberately don't count, they
## grow every tick, which is what this cache can't represent.
func node_count(tier: StringName) -> float:
	return float(manual_counts.get(tier, 0))

func biome_size(key: StringName) -> float:
	return float(biome_sizes.get(key, 0))
