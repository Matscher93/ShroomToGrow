class_name UpgradeEffect 
extends Resource

enum Op { ADD, INCREASED, MORE }      # flat add, additive %, multiplicative %
enum Scope { GLOBAL, TAG, NODE }

@export var stat: StringName          # &"nutrient_production", &"tick_rate"...
@export var op: Op = Op.INCREASED
@export var scope: Scope = Scope.GLOBAL
@export var target: StringName = &""  # tag ("mycelium") or node id; empty = global
@export var per_level: float = 0.0
@export var dependency: ScalingSource  # extra multiplier on the effect magnitude, e.g. manual node count
