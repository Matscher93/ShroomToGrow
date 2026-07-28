class_name PerkBranchDef
extends Resource
## MODEL — one arm of the mycelial web. Adding a new branch is just adding
## one of these (+ its effect) to all_branches.tres — PerkTree generates the
## 6-node tier chain and UpgradeSystem picks the effect up automatically.

@export var key: StringName
@export var label: String
@export var angle_degrees: float
@export var hue: float

## Effect for each tier (0-indexed: I, II, III, IV), independently leveled.
## Most branches use a single shared effect — e.g. every Substrate node adds
## +15% node_production per level, all stacking into the same UpgradeSystem
## stat bucket. A branch can instead give each tier its own effect (e.g. one
## targets Meadow, the next Forest); when a tier has no entry of its own,
## effect_for_tier() falls back to the last one in the array.
@export var effects: Array[UpgradeEffectDef] = []

func effect_for_tier(tier: int) -> UpgradeEffectDef:
	return effects[mini(tier, effects.size() - 1)]
