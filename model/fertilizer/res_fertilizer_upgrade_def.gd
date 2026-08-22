class_name FertilizerUpgradeDef
extends Resource
## MODEL: static definition of one fertilizer upgrade - which producers it raises,
## by how much per level, and what the first level costs.
##
## The stat, scope and target are not repeated here: `currencies` points at the
## CurrencyDefs the growth producers already name, and FertilizerTree copies each
## producer's own stat/scope/target off the matching GrowthProducerDef. A producer
## retargeted once is retargeted for this track too.

@export var id: StringName

@export var display_name: String
@export_multiline var description: String

## The producers this upgrade raises. One UpgradeEffectDef is generated per entry,
## so an upgrade covering every producer lists all four.
@export var currencies: Array[CurrencyDef] = []

## Fraction one level adds, on top of 1.0. Stacks add rather than compound - three
## levels of +10% is x1.3, not x1.331 - matching GrowthProducerDef.lp_per_level.
@export var per_level: float = 0.10

## Fertilizer the first level costs. A plain float rather than the exportable
## BigNumber pair UpgradeDef uses: these costs are single and double digits, and
## doubling from 3 cannot leave float range in any reachable number of levels.
@export var base_cost: float = 3.0

## Each level multiplies the cost by this. 2.0 gives the doubling ladder
## base * 2^level.
@export var cost_growth: float = 2.0
