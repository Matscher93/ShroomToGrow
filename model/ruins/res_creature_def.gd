class_name CreatureDef
extends Resource
## MODEL: static definition of one controllable creature. What it costs to take
## over, how far it can be pushed, and what it is good at.

@export var id: StringName
@export var display_name: String
@export_multiline var description: String

## Missions this creature is suited to, by MissionDef.id. Running one of these
## applies affinity_bonus on top of the creature's own speed and yield.
@export var affinity: Array[StringName] = []

## Per-rank multipliers. Rank 1 applies these once, rank 2 twice, and so on -
## LINEAR rather than compounding, so a long roster stays legible.
@export var speed_per_rank: float = 0.15
@export var yield_per_rank: float = 0.20

## What running an affinity mission is worth, applied to both speed and yield.
@export var affinity_bonus: float = 0.5

## Ranks this creature may reach before &"creature_rank_cap" raises it.
@export var base_rank_cap: int = 5

## Missions collected before this creature may be taken over at all.
@export var min_missions_completed: int = 0

@export var recruit_currency: CurrencyDef
@export var _recruit_cost_mantissa: float = 1.0
@export var _recruit_cost_exponent: int = 1
var recruit_cost: BigNumber:
	get: return BigNumber.new(_recruit_cost_mantissa, _recruit_cost_exponent)
	set(value):
		_recruit_cost_mantissa = value.mantissa
		_recruit_cost_exponent = value.exponent

## Cost curve for ranking up, paid in rank_currency: base * growth^(rank - 1).
@export var rank_currency: CurrencyDef
@export var _rank_base_cost_mantissa: float = 2.0
@export var _rank_base_cost_exponent: int = 1
var rank_base_cost: BigNumber:
	get: return BigNumber.new(_rank_base_cost_mantissa, _rank_base_cost_exponent)
	set(value):
		_rank_base_cost_mantissa = value.mantissa
		_rank_base_cost_exponent = value.exponent

@export var rank_cost_growth: float = 1.8
