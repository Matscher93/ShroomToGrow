class_name PerkNodeDef
extends Resource
## MODEL — one hand-authored perk in a branch. Everything the designer tunes
## per node lives here; PerkTree turns these into PerkDefs and computes where
## they sit on the web from the nesting alone.

## Unique across the whole perk tree, and used verbatim as the perk's runtime
## id — so renaming one orphans that perk's saved level (see SaveManager's
## migration table).
@export var id: StringName

## The perks that grow out of this one. Like every other data resource here, a
## node points at its descendants; nothing points back up at its parent.
@export var children: Array[PerkNodeDef] = []

@export var display_name: String
@export_multiline var description: String
@export var max_level: int = 5

@export var base_cost: float = 2.0
@export var cost_growth: float = 1.6

## Empty falls back to the branch's default_effects — most branches give every
## node the same effect and only need to fill this in for the odd one out.
@export var effects: Array[UpgradeEffectDef] = []
