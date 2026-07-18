class_name UpgradeDef 
extends Resource

@export var id: StringName
@export var display_name: String
@export_multiline var description: String
@export var max_level: int = 0        # 0 = infinite
@export var base_cost: float = 10.0
@export var cost_growth: float = 1.15
@export var effects: Array[UpgradeEffect] = []
@export var unlocks: Array[StringName] = []  
