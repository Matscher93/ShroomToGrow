class_name PerkDef
extends UpgradeDef
## MODEL: one node in the mycelial web. An UpgradeDef (cost, level and effects
## reused as-is) plus the graph metadata PerkTree needs to place and connect it.
## Never hand-authored, PerkTree.build() generates one per PerkNodeDef.

@export var parent_id: StringName  ## &"" for the core node
@export var branch_key: StringName ## &"" for the core node
@export var world_x: float
@export var world_y: float
