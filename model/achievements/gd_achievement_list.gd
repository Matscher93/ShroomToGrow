class_name AchievementList
extends Resource
## MODEL: ordered registry of every AchievementDef, loaded once by App. Mirrors
## BiomeList / MyceliumNodes, a thin @export Array wrapper the editor can author.
##
## An explicit array rather than a folder walk (as the upgrade tracks use), so
## the archive's display order is authored rather than whatever order DirAccess
## happens to return.

@export var achievements: Array[AchievementDef]
