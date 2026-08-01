class_name PerkBranchDef
extends Resource
## MODEL — one arm of the mycelial web: its colour plus the perks that grow
## along it. Shape is free-form — each node nests its own children, and PerkTree
## lays the branch out from that nesting. Direction isn't authored either: the
## branches are spread evenly around the core in the order PerkBranchList lists
## them.

@export var key: StringName
@export var label: String
@export var hue: float

## Used by any node that declares no effects of its own — e.g. every Substrate
## node adds +15% node_production per level into the same UpgradeSystem stat
## bucket, so only the branch needs to say so.
@export var default_effects: Array[UpgradeEffectDef] = []

## The nodes hanging straight off the core; everything deeper hangs off these.
@export var roots: Array[PerkNodeDef] = []

func effects_for(node: PerkNodeDef) -> Array[UpgradeEffectDef]:
	return node.effects if not node.effects.is_empty() else default_effects
