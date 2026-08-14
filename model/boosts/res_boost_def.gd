class_name BoostDef
extends Resource
## MODEL: static definition of one crystal-bought boost - what stat it raises,
## how fast its payoff climbs across tiers, and what it costs.
##
## Both curves live here rather than in BoostTiers so two boosts can be shaped
## differently: a cheap, shallow one and an expensive, steep one are a data edit,
## not a second ladder. BoostTiers keeps only what every boost shares - how many
## levels a tier holds and how many tiers there are.

@export var id: StringName
@export var display_name: String
@export_multiline var description: String

## The stat every tier of this boost writes into, e.g. &"node_production".
## Must be one ProductionSystem already stacks, or the boost is a no-op.
@export var stat: StringName

## How far the boost reaches, and what it reaches. GLOBAL with an empty target is
## the usual case.
##
## NODE with target &"0" is how a &"node_production" boost is kept to nutrient
## output alone: tier 0 is the only node whose production becomes nutrients, and
## every tier above it feeds the tier below. A global &"node_production" boost
## multiplies *every* link in that chain, so by the time it reaches nutrients it
## has been applied once per tier - a x1.5 boost lands as x1.5^10, which is not
## what "boost nutrient production" means.
@export var scope: UpgradeEffectDef.Scope = UpgradeEffectDef.Scope.GLOBAL
@export var target: StringName = &""

# ---------------------------------------------------------------- bonus curve

## A tier-1 level multiplies by 1 + base_per_level. Levels compound, so a full
## tier of 100 is worth (1 + base_per_level)^100, not 100 times one level.
@export var base_per_level: float = 0.01

## How much more a level is worth one tier up. 5.0 gives x1.01, x1.05, x1.25,
## x2.25, x7.25 per level across the five tiers.
##
## Must be at least 1.0: below it a tier pays *less* per level than the one under
## it, so crossing a boundary is a downgrade the player paid for.
@export var per_level_growth: float = 5.0

# ---------------------------------------------------------------- cost curve

## Crystals for the first level of tier 1. Every tier restarts its own curve from
## tier_base_cost(), which is this scaled up by tier_cost_growth.
@export var base_cost: float = 1.0

## Per-level growth *within* a tier.
@export var cost_growth: float = 1.05

## Per-tier growth of the starting price. Prices restart at each boundary, and
## without this they restart at the same number every time - so tier 5, worth
## orders of magnitude more per level, would open at the same crystal price
## tier 1 did.
##
## Must be greater than 1.0, or the tiers do not escalate at all.
@export var tier_cost_growth: float = 10.0

# ---------------------------------------------------------------- perk gates

## Prestige perk that opens this boost for buying, empty for one that needs none.
## Same contract as AutomationDef.unlock_perk_id: perks survive a prestige, and
## locking only blocks further purchases - levels already bought keep paying out.
@export var unlock_perk_id: StringName = &""

## How far up the ladder this boost may be bought before a perk widens it.
## 0 = the whole BoostTiers ladder, i.e. no gate of its own.
@export var base_max_level: int = 0

## Perk whose levels raise that ceiling, and by how many levels each. The result
## is still clamped to BoostTiers.max_level() - the ladder's tiers are what the
## rates and prices are authored against, so nothing may reach past them.
@export var max_level_perk_id: StringName = &""
@export var max_level_per_perk_level: int = 0

## Fraction one level of the given tier multiplies by on top of 1.0, e.g. 0.05
## for a x1.05 per level.
func per_level(tier: int) -> float:
	return base_per_level * pow(per_level_growth, float(tier - 1))

## Crystals the first level of the given tier costs, before the within-tier
## curve.
func tier_base_cost(tier: int) -> float:
	return base_cost * pow(tier_cost_growth, float(tier - 1))
