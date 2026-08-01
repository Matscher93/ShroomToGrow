class_name PerkNodeDef
extends Resource
## MODEL: one hand-authored perk in a branch. Everything tuned per node lives
## here. PerkTree turns these into PerkDefs and derives their web position from
## the nesting alone.

## Unique across the perk tree and used verbatim as the runtime id, so renaming
## one orphans that perk's saved level (see SaveManager's migration table).
@export var id: StringName

## The perks growing out of this one. Like every other data resource here, a
## node points at its descendants and nothing points back up at its parent.
@export var children: Array[PerkNodeDef] = []

@export var display_name: String
@export_multiline var description: String
@export var max_level: int = 5

# BigNumber split into exportable parts, same trick as UpgradeDef, so deep
# branches can be priced past float range. Read/write via base_cost below.
@export var _base_cost_mantissa: float = 2.0
@export var _base_cost_exponent: int = 0
var base_cost: BigNumber:
	get: return BigNumber.new(_base_cost_mantissa, _base_cost_exponent)
	set(value):
		_base_cost_mantissa = value.mantissa
		_base_cost_exponent = value.exponent

@export var cost_growth: float = 1.6

## Empty falls back to the branch's default_effects. Most branches give every
## node the same effect and only fill this in for the odd one out.
@export var effects: Array[UpgradeEffectDef] = []
