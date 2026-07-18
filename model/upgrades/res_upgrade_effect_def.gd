class_name UpgradeEffect 
extends Resource

enum Op { ADD, INCREASED, MORE }      # flat add, additive %, multiplicative %
enum Scope { GLOBAL, TAG, NODE }
enum LevelScaling { LINEAR, COMPOUND } # per_level*level  vs  (1+per_level)^level - 1

@export var stat: StringName          # &"nutrient_production", &"tick_rate"...
@export var op: Op = Op.INCREASED
@export var scope: Scope = Scope.GLOBAL
@export var target: StringName = &""  # tag ("mycelium") or node id; empty = global
@export var per_level: float = 0.0
@export var level_scaling: LevelScaling = LevelScaling.LINEAR
@export var dependency: ScalingSource  # extra multiplier on the effect magnitude, e.g. manual node count

## This effect's own magnitude at the given upgrade level, before dependency scaling.
func magnitude(lvl: int) -> BigNumber:
	if level_scaling == LevelScaling.COMPOUND:
		return BigNumber.from_value(1.0 + per_level).pow_float(float(lvl)).sub(BigNumber.from_value(1.0))
	return BigNumber.from_value(per_level).scale(float(lvl))
