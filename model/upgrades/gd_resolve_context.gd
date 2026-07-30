class_name ResolveContext
extends RefCounted
## MODEL — the live inputs a ScalingSourceDef can scale an upgrade effect by.
##
## Everything here must be *player-action driven*, not per-tick: UpgradeSystem
## resolves these into a cache that is only rebuilt on invalidate(), so a value
## that moved every tick would be read stale. Whoever writes a field is also
## responsible for invalidating the affected systems (see App._track_manual_count
## and App.buy_biome_size).
##
## node_counts / resources / stat_snapshot used to live here for the STAT and
## RESOURCE scaling kinds. Nothing ever wrote them, so those kinds resolved to
## 0.0 and silently zeroed any effect that depended on one; both they and the
## fields are gone (see ScalingSourceDef.Kind).

var manual_counts: Dictionary = {}    # node tier -> hand-bought count
var biome_sizes: Dictionary = {}      # biome key -> purchased size

## Hand-bought nodes only. Auto-generated nodes deliberately don't count — they
## grow every tick, which is exactly what this cache can't represent.
func node_count(tier: StringName) -> float:
	return float(manual_counts.get(tier, 0))

func biome_size(key: StringName) -> float:
	return float(biome_sizes.get(key, 0))
