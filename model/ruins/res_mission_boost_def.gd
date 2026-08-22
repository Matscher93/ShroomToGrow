class_name MissionBoostDef
extends Resource
## MODEL: one rung of the Ruins boost ladder, priced in one of the three mission
## currencies.
##
## The general/control split is nothing but which stat an effect names: a rung
## writing &"node_production" moves the colony, one writing &"mission_speed" moves
## the board. Neither needs code here.

@export var id: StringName
@export var display_name: String
@export_multiline var description: String

## Which of the three mission currencies buys this. UpgradeSystem.buy() spends by
## PlayerData field name, which CurrencyTypes.field_for() derives from this.
@export var currency: CurrencyDef

@export var _base_cost_mantissa: float = 1.0
@export var _base_cost_exponent: int = 1
var base_cost: BigNumber:
	get: return BigNumber.new(_base_cost_mantissa, _base_cost_exponent)
	set(value):
		_base_cost_mantissa = value.mantissa
		_base_cost_exponent = value.exponent

@export var cost_growth: float = 1.5

## 0 = unlimited.
@export var max_level: int = 0

## Missions collected before this rung opens, so the ladder reveals itself as the
## board is worked - same gate shape as MissionDef.min_missions_completed.
@export var min_missions_completed: int = 0

@export var effects: Array[UpgradeEffectDef] = []
