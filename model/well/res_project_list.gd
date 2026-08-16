class_name ProjectList
extends Resource
## MODEL: every authored well project, in display order. Parallel to BoostList /
## BiomeList / PerkBranchList.

@export var projects: Array[ProjectDef] = []

## Prestige perk that raises how far *every* project can be funded, and by how
## many levels each of its own levels is worth.
##
## Authored on the list rather than per project because it lifts the whole
## ladder: repeating the same two fields across every ProjectDef would be one
## more place to forget when a project is added, for a value none of them is ever
## meant to disagree on.
##
## Same contract as BoostDef.max_level_perk_id otherwise: perks survive a
## sporation, and a project already past a lowered ceiling keeps its levels and
## keeps paying out - the cap only blocks further funding.
@export var max_level_perk_id: StringName = &""
@export var max_level_per_perk_level: int = 0
