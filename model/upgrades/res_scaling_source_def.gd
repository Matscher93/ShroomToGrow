class_name ScalingSourceDef
extends Resource

## Only sources that change on a *player action* belong here. UpgradeSystem
## resolves these into a cache that is rebuilt on invalidate(), never per tick,
## so a source that moves every tick would be read stale.
##
## STAT (= 2) and RESOURCE (= 3) used to sit between NODE_COUNT and BIOME_SIZE.
## Both read ResolveContext fields that nothing ever wrote, so they evaluated to
## 0.0 and silently zeroed the magnitude of any effect depending on them — and
## both are live-per-tick, so they can't be reinstated without a resolution pass
## the cache design doesn't have. The remaining values keep their original
## ordinals so the authored .tres files still deserialise correctly.
enum Kind { NONE = 0, NODE_COUNT = 1, BIOME_SIZE = 4 }
enum Transform { NONE, SQRT, LOG10 }

@export var kind: Kind = Kind.NONE
@export var key: StringName = &""       # node tier id or biome key
@export var transform: Transform = Transform.NONE

func evaluate(ctx: ResolveContext) -> float:
	var v := 1.0
	match kind:
		Kind.NONE:       return 1.0
		Kind.NODE_COUNT: v = ctx.node_count(key)
		Kind.BIOME_SIZE: v = ctx.biome_size(key)
		_:
			push_error("ScalingSourceDef '%s' has unsupported kind %d — treating as 1.0." % [key, kind])
			return 1.0
	match transform:
		Transform.SQRT:  return sqrt(max(0.0, v))
		Transform.LOG10: return log(max(1.0, v)) / log(10.0)
		_:               return v
