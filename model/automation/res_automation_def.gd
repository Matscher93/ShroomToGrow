class_name AutomationDef
extends Resource
## MODEL: static definition of one crystal-bought automation. What it buys on
## the player's behalf, what a level costs and how often it fires.
## Parallel to BiomeDef / AchievementDef / UpgradeDef.

## What one firing does. Every entry has to be handled by AutomationSystem.run(),
## or the automation ticks and does nothing.
enum Kind {
	BUY_NODES,           ## one mycelium node, highest affordable tier first
	BUY_BIOME_SIZE,      ## one Biome Size level, cheapest affordable biome
	BUY_SYMBIOSIS,       ## one potency/synergy level, cheapest affordable
	SPEND_BIOME_POINTS,  ## one biome upgrade, following the player's point plan
}

@export var id: StringName
@export var display_name: String
@export_multiline var description: String
@export var sort_order: int = 0
@export var kind: Kind

## Crystal cost of the next level: base_cost * cost_growth^(level^cost_growth_exponent).
## Same curve shape as UpgradeSystem.cost().
@export var _base_cost_mantissa: float = 1.0
@export var _base_cost_exponent: int = 1
var base_cost: BigNumber:
	get: return BigNumber.new(_base_cost_mantissa, _base_cost_exponent)
	set(value):
		_base_cost_mantissa = value.mantissa
		_base_cost_exponent = value.exponent

@export var cost_growth: float = 1.6
@export var cost_growth_exponent: float = 1.0
@export var max_level: int = 0  ## 0 = infinite

## Automations fire off the game tick, never off a clock of their own, so they
## can only ever act while the player is actually playing.
##
## Actions per tick at level 1. Below 1.0 the automation fires every few ticks
## instead: AutomationSystem carries the fraction over between ticks rather than
## rounding it away, so 0.25 is reliably one action every four ticks.
@export var base_runs_per_tick: float = 0.25
## Added per level past the first, before &"automation_rate" scales the total.
@export var runs_per_level: float = 0.25
