class_name AutomationList
extends Resource
## MODEL: ordered registry of every AutomationDef, loaded once by App. Mirrors
## BiomeList / AchievementList, a thin @export Array wrapper the editor can
## author.

@export var automations: Array[AutomationDef]
