class_name UpgradeDef 
extends Resource

@export var id: StringName
@export var display_name: String
@export_multiline var description: String
@export var max_level: int = 0        # 0 = infinite

# BigNumber, split into exportable parts — initial costs can exceed float range
# at high tiers/levels. Use base_cost (below) to read/write as a BigNumber.
@export var _base_cost_mantissa: float = 1.0
@export var _base_cost_exponent: int = 1
var base_cost: BigNumber:
	get: return BigNumber.new(_base_cost_mantissa, _base_cost_exponent)
	set(value):
		_base_cost_mantissa = value.mantissa
		_base_cost_exponent = value.exponent

@export var cost_growth: float = 1.15
@export var cost_growth_exponent: float = 1.0  # >1 makes the cost curve steepen with level
@export var effects: Array[UpgradeEffect] = []
@export var unlocks: Array[StringName] = []  
