class_name ProjectDef
extends Resource
## MODEL: static definition of one well project - what funding it costs in
## water, how far it can be funded, and the ladder of boons that funding opens.
##
## Parallel to BoostDef: the authored resource describes the thing, and the
## UpgradeDefs holding its levels are derived by ProjectTree rather than
## hand-written.

@export var id: StringName
@export var display_name: String
@export_multiline var description: String

## Times this project can be funded. 0 = unlimited, but a boon's own ceiling is
## derived from this, so an unlimited project's boons are unlimited too.
@export var max_level: int = 0

# BigNumber split into exportable parts, same trick as UpgradeDef, so a late
# project can be priced past float range. Read/write via base_cost below.
@export var _base_cost_mantissa: float = 1.0
@export var _base_cost_exponent: int = 1
var base_cost: BigNumber:
	get: return BigNumber.new(_base_cost_mantissa, _base_cost_exponent)
	set(value):
		_base_cost_mantissa = value.mantissa
		_base_cost_exponent = value.exponent

## Water the next funding costs: base_cost * cost_growth^(level * cost_growth_exponent^level).
@export var cost_growth: float = 1.35
@export var cost_growth_exponent: float = 1.0  ## >1 steepens the cost curve with level

## In ladder order. The first entry must have unlock_at_level 1: it is the boon
## carrying this project's level and price (see ProjectTree).
@export var boons: Array[ProjectBoonDef] = []

## Fundings across *every* project before this one opens. 0 = open from the
## start, and at least one project has to be, or the well can never be started.
##
## Same shape as UpgradeDef.min_biome_points_spent: the gate is the investment
## already made in the track, not a purchase in some other one. That keeps the
## Well a self-contained ladder - a player who has found the lake can work
## through all of it without waiting on a sporation.
##
## Like every other gate here, locking only blocks further funding: levels bought
## before a rebalance moved the threshold keep paying out.
@export var min_project_levels: int = 0
