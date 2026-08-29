class_name HeroDef
extends Resource
## MODEL: static definition of one hero unit - what it costs to take over, how
## far it can be pushed, and which currencies its chain pays in.
##
## A hero owns exactly one expedition chain and runs nothing else. Farms are the
## workers' half of the Ruins, and a hero is never assigned to one: what a hero
## is for is walking its own chain, and levelling it is what opens the rest of
## that chain rather than a number on a ladder shared with everybody else.

@export var id: StringName
@export var display_name: String
@export_multiline var description: String

## Per-level multipliers. Level 1 applies these once, level 2 twice, and so on -
## LINEAR rather than compounding, so a long roster stays legible.
@export var speed_per_level: float = 0.15
@export var yield_per_level: float = 0.20

## Levels this hero may reach before &"hero_level_cap" raises it.
@export var base_level_cap: int = 5

## Missions collected before this hero may be taken over at all.
@export var min_missions_completed: int = 0

## The currencies every expedition and farm in this hero's chain pays in. One for
## the first three heroes, two for the next three, all three for the last.
##
## Authored rather than left implicit so the integrity sweep can hold the rule:
## a chain that quietly starts paying a fourth currency, or the wrong one, is the
## kind of drift nothing else would catch.
@export var payout_currencies: Array[CurrencyDef] = []

@export var recruit_currency: CurrencyDef
@export var _recruit_cost_mantissa: float = 1.0
@export var _recruit_cost_exponent: int = 1
var recruit_cost: BigNumber:
	get: return BigNumber.new(_recruit_cost_mantissa, _recruit_cost_exponent)
	set(value):
		_recruit_cost_mantissa = value.mantissa
		_recruit_cost_exponent = value.exponent

## Cost curve for levelling up, paid in level_currency: base * growth^(level - 1).
@export var level_currency: CurrencyDef
@export var _level_base_cost_mantissa: float = 2.0
@export var _level_base_cost_exponent: int = 1
var level_base_cost: BigNumber:
	get: return BigNumber.new(_level_base_cost_mantissa, _level_base_cost_exponent)
	set(value):
		_level_base_cost_mantissa = value.mantissa
		_level_base_cost_exponent = value.exponent

@export var level_cost_growth: float = 1.8

## Further currencies charged alongside recruit_cost, for a hero whose price is
## not one currency. Empty for all but the last, which costs all three at once.
##
## A MissionPayoutDef because it is the same shape - a currency and a BigNumber -
## and reusing it means the price round-trips and displays exactly as a payout
## does rather than needing a second resource that says the same thing.
@export var extra_recruit_costs: Array[MissionPayoutDef] = []
