class_name PerkBranchDef
extends Resource
## MODEL: one arm of the mycelial web, its colour plus the perks growing along
## it. Shape is free-form, each node nests its children and PerkTree lays the
## branch out from that nesting. Direction isn't authored either: branches are
## spread evenly around the core in PerkBranchList order.

@export var key: StringName
@export var label: String
@export var hue: float

## Used by any node declaring no effects of its own. Every Substrate node adds
## +15% node_production per level into the same stat bucket, for example, so
## only the branch needs to say so.
@export var default_effects: Array[UpgradeEffectDef] = []

## The nodes hanging straight off the core. Everything deeper hangs off these.
@export var roots: Array[PerkNodeDef] = []

func effects_for(node: PerkNodeDef) -> Array[UpgradeEffectDef]:
	return node.effects if not node.effects.is_empty() else default_effects
