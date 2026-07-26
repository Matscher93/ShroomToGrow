class_name BiomeDef
extends Resource
## MODEL — static definition of one biome: what it unlocks, what it costs,
## and where its XP comes from. Parallel to MyceliumNode / UpgradeDef.

enum XpSource { TOTAL_NODES, SYMBIOSIS_LEVELS, PRESTIGE_COUNT }

@export var key: StringName
@export var display_name: String
@export_multiline var description: String
@export var screen_type: ScreenTypes.Types
@export var xp_source: XpSource
@export var xp_label: String  ## e.g. "nodes grown" — used in level-progress display

@export var biome_color: Color
@export var biome_shader: Shader  ## assigned to a ColorRect's material to render biome's icon

## True for the starter biome(s) — unlocked from a fresh save, no cost/currency needed.
@export var always_unlocked: bool = false
@export var unlock_currency: CurrencyTypes.Types = CurrencyTypes.Types.NUTRIENTS

@export var _unlock_cost_mantissa: float = 0.0
@export var _unlock_cost_exponent: int = 0
var unlock_cost: BigNumber:
	get: return BigNumber.new(_unlock_cost_mantissa, _unlock_cost_exponent)
	set(value):
		_unlock_cost_mantissa = value.mantissa
		_unlock_cost_exponent = value.exponent

## Cost curve for buying Biome Size, paid in nutrients: size_base_cost * size_cost_growth^(size^size_cost_growth_exponent).
@export var _size_base_cost_mantissa: float = 1.0
@export var _size_base_cost_exponent: int = 0
var size_base_cost: BigNumber:
	get: return BigNumber.new(_size_base_cost_mantissa, _size_base_cost_exponent)
	set(value):
		_size_base_cost_mantissa = value.mantissa
		_size_base_cost_exponent = value.exponent

@export var size_cost_growth: float = 1.15
@export var size_cost_growth_exponent: float = 1.0
