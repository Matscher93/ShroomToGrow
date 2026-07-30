class_name PerkNodeDef
extends Resource
## MODEL — one hand-authored perk in a branch. Everything the designer tunes
## per node lives here; PerkTree turns these into PerkDefs and computes where
## they sit on the web from the parent links alone.

## Unique within its branch. The perk's runtime id is branch_key + key,
## so renaming a key orphans that perk's saved level.
@export var key: StringName
## Key of the node this one grows out of, within the same branch.
## &"" attaches it straight to the core.
@export var parent_key: StringName

@export var display_name: String
@export_multiline var description: String
@export var max_level: int = 5

@export var base_cost: float = 2.0
@export var cost_growth: float = 1.6

## Empty falls back to the branch's default_effects — most branches give every
## node the same effect and only need to fill this in for the odd one out.
@export var effects: Array[UpgradeEffectDef] = []
