class_name ScalingSource extends Resource

enum Kind { NONE, NODE_COUNT, STAT, RESOURCE }
enum Transform { NONE, SQRT, LOG10 }

@export var kind: Kind = Kind.NONE
@export var key: StringName = &""       # tier id / stat id / resource id
@export var manual_only: bool = true    # NODE_COUNT: only hand-bought nodes
@export var transform: Transform = Transform.NONE

func evaluate(ctx: ResolveContext) -> float:
	var v := 1.0
	match kind:
		Kind.NONE:       return 1.0
		Kind.NODE_COUNT: v = ctx.node_count(key, manual_only)
		Kind.STAT:       v = ctx.stat_value(key)
		Kind.RESOURCE:   v = ctx.resource_amount(key)
	match transform:
		Transform.SQRT:  return sqrt(max(0.0, v))
		Transform.LOG10: return log(max(1.0, v)) / log(10.0)
		_:               return v

# Source changes every tick (live) vs only on player actions (cacheable)?
func is_live() -> bool:
	return kind == Kind.STAT or kind == Kind.RESOURCE
