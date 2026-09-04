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
var biome_levels: Dictionary = {}     # biome key -> BiomeCalculator level

## Hand-bought nodes only. Auto-generated nodes deliberately don't count, they
## grow every tick, which is what this cache can't represent.
func node_count(tier: StringName) -> float:
	return float(manual_counts.get(tier, 0))

## One higher than the purchased Biome Size, so an unbought biome multiplies by
## 1.0 instead of 0.0. A raw size would make every BIOME_SIZE-scaled upgrade a
## permanent no-op until the first Size purchase: levelling it would keep
## reading "now +0%", which looks like broken UI rather than a dead upgrade.
func biome_size(key: StringName) -> float:
	return float(biome_sizes.get(key, 0)) + 1.0

## The biome's level, and 1.0 for one nothing has written yet - the level a biome
## sits at before it has earned any XP, so an unwritten entry scales an effect by
## the same amount the first level does rather than erasing it.
##
## The one entry here that is not written by a single player action: a biome's
## level is derived from six different XP sources (BiomeCalculator.xp_for), two
## of which - achievement tiers and missions completed - can move on a tick. See
## BiomeSystem.sync_levels(), which pulls all of them and invalidates only when a
## level actually moved, so this stays as cache-safe as the two above.
func biome_level(key: StringName) -> float:
	return float(biome_levels.get(key, 1))
