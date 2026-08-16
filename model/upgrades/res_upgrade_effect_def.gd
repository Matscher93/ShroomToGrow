class_name UpgradeEffectDef
extends Resource

enum Op { ADD, INCREASED, MORE }      # flat add, additive %, multiplicative %
enum Scope { GLOBAL, TAG, NODE }
enum LevelScaling { LINEAR, COMPOUND } # per_level*level  vs  (1+per_level)^level - 1

@export var stat: StringName          # &"nutrient_production", &"tick_rate"...
@export var op: Op = Op.INCREASED
@export var scope: Scope = Scope.GLOBAL
@export var target: StringName = &""  # tag ("mycelium") or node id, empty = global
@export var per_level: float = 0.0
@export var level_scaling: LevelScaling = LevelScaling.LINEAR
@export var dependency: ScalingSourceDef  # extra multiplier on magnitude, e.g. manual node count

## Ceiling on what this effect may ever contribute, in the same units per_level
## is authored in: seconds for an ADD on &"tick_rate", a fraction for an
## INCREASED, the amount above 1.0 for a MORE. 0 = uncapped.
##
## Applied as a bound on the absolute value, so it caps a negative per_level the
## same way it caps a positive one: -0.05/level with a cap of 1.0 stops at -1.0
## rather than running to -3.0. A signed bound would need every caller to know
## which direction its stat improves in.
@export var max_magnitude: float = 0.0

## This effect's magnitude at the given upgrade level, before dependency scaling
## and before the cap. Callers wanting what the effect actually contributes want
## contribution() instead.
func magnitude(lvl: int) -> BigNumber:
	if level_scaling == LevelScaling.COMPOUND:
		return BigNumber.from_value(1.0 + per_level).pow_float(float(lvl)).sub(BigNumber.from_value(1.0))
	return BigNumber.from_value(per_level).scale(float(lvl))

## What this effect actually adds to its stat bucket at `lvl`: its magnitude,
## scaled by any ScalingSourceDef, then capped.
##
## The cap goes last, after the dependency rather than before it, so
## max_magnitude always means "the most this effect can contribute". Capping the
## magnitude alone would leave a Size-scaled upgrade free to multiply its way
## past the ceiling it authored, which is the one thing the field exists to stop.
##
## Every read of an effect's size goes through here, so a capped effect resolves,
## displays and previews as the same number.
func contribution(lvl: int, ctx: ResolveContext) -> BigNumber:
	var mag := magnitude(lvl)
	if dependency:
		mag = mag.scale(dependency.evaluate(ctx))
	if max_magnitude <= 0.0:
		return mag
	var ceiling := BigNumber.from_value(max_magnitude)
	if mag.gt(ceiling):
		return ceiling
	var floor_value := BigNumber.from_value(-max_magnitude)
	if mag.lt(floor_value):
		return floor_value
	return mag
