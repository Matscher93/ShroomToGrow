class_name PerkBranchDef
extends Resource
## MODEL — one arm of the mycelial web. Adding a new branch is just adding
## one of these (+ its effect) to all_branches.tres — PerkTree generates the
## 6-node tier chain and UpgradeSystem picks the effect up automatically.

@export var key: StringName
@export var label: String
@export var angle_degrees: float
@export var hue: float

## Every tier-node in this branch shares this same effect (independently
## leveled) — e.g. every Substrate node adds +15% node_production per level,
## and they all stack into the same UpgradeSystem stat bucket.
@export var effect: UpgradeEffect
