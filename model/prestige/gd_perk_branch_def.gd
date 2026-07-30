class_name PerkBranchDef
extends Resource
## MODEL — one arm of the mycelial web: its direction/colour plus the perks
## that grow along it. Shape is free-form — nodes chain and fork purely by
## their parent_key, and PerkTree lays them out from that.

@export var key: StringName
@export var label: String
@export var angle_degrees: float
@export var hue: float

## Used by any node that declares no effects of its own — e.g. every Substrate
## node adds +15% node_production per level into the same UpgradeSystem stat
## bucket, so only the branch needs to say so.
@export var default_effects: Array[UpgradeEffectDef] = []

@export var nodes: Array[PerkNodeDef] = []

func effects_for(node: PerkNodeDef) -> Array[UpgradeEffectDef]:
	return node.effects if not node.effects.is_empty() else default_effects
