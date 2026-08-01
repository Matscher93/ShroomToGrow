class_name UpgradeDef
extends Resource

@export var id: StringName
@export var display_name: String
@export_multiline var description: String
@export var max_level: int = 0        # 0 = infinite

# BigNumber split into exportable parts, since initial costs can exceed float
# range at high tiers. Read/write via base_cost below.
@export var _base_cost_mantissa: float = 1.0
@export var _base_cost_exponent: int = 1
var base_cost: BigNumber:
	get: return BigNumber.new(_base_cost_mantissa, _base_cost_exponent)
	set(value):
		_base_cost_mantissa = value.mantissa
		_base_cost_exponent = value.exponent

@export var cost_growth: float = 1.15
@export var cost_growth_exponent: float = 1.0  # >1 steepens the cost curve with level
@export var effects: Array[UpgradeEffectDef] = []

## Biome upgrades only: total points spent in that biome, across all its
## upgrades, before this one is purchasable. 0 = always available.
@export var min_biome_points_spent: int = 0
