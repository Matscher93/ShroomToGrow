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
## x2.25, x7.25 per level across a five-tier ladder, and keeps climbing at that
## rate if BoostList authors more tiers than that.
##
## Must be at least 1.0: below it a tier pays *less* per level than the one under
## it, so crossing a boundary is a downgrade the player paid for.
@export var per_level_growth: float = 5.0

# ---------------------------------------------------------------- cost curve

## Crystals for the first level of tier 1. Every level above it is this climbed by
## cost_growth, across tier boundaries as well as within a tier.
@export var base_cost: float = 1.0

## Per-level growth. Applies to the whole ladder, not to one tier: the levels of
## the tiers below count towards the exponent, so a boundary is one more step of
## this curve rather than a fresh start.
@export var cost_growth: float = 1.05

## Bends that climb upwards with the level itself, the same shape
## UpgradeDef.cost_growth_exponent has: the level is raised through this before it
## becomes cost_growth's exponent, so the price curves in log space instead of
## running as a straight line.
##
## Compounds far harder here than on the ladders it is borrowed from. The shipped
## node curves sit between 1.01 and 1.044 over fifty levels; this ladder is five
## hundred, and 1.01 over five hundred levels is already past what a float holds.
## Reach for the third decimal, and read the chart rather than the number.
##
## 1.0 is the plain geometric ladder, which is what every boost shipped with.
@export_range(1.0, 1.02, 0.0001, "or_greater") var cost_growth_exponent: float = 1.0

## Extra step taken *on top of* that continuity when a tier opens, e.g. 2.0 to
## make crossing a boundary cost double what the next level otherwise would.
##
## 1.0 is the smooth ladder, not a free one. Below 1.0 a boundary becomes a
## discount - the same contract per_level_growth has, and for the same reason:
## a player must never be paid to cross into a tier that is worth more.
@export var tier_cost_growth: float = 1.0

# ---------------------------------------------------------------- perk gates

## Prestige perk that opens this boost for buying, empty for one that needs none.
## Same contract as AutomationDef.unlock_perk_id: perks survive a prestige, and
## locking only blocks further purchases - levels already bought keep paying out.
@export var unlock_perk_id: StringName = &""

## How far up the ladder this boost may be bought before a perk widens it.
##
## 0 means no ceiling at all, not a default one: the ladder has no last tier to
## fall back on, so an ungated boost climbs for as long as the price allows. Every
## shipped boost sets this and leans on its cap perk for the rest.
@export var base_max_level: int = 0

## Perk whose levels raise that ceiling, and by how many levels each.
##
## Nothing clamps the result. The ladder tiers up to meet however far the perk
## reaches, so the levels it opens are bought at the rate and the price of the
## tier they actually land in rather than piling into a last one.
@export var max_level_perk_id: StringName = &""
@export var max_level_per_perk_level: int = 0

## Fraction one level of the given tier multiplies by on top of 1.0, e.g. 0.05
## for a x1.05 per level.
func per_level(tier: int) -> float:
	return base_per_level * pow(per_level_growth, float(tier - 1))

## Crystals the next level costs, given how far up the whole ladder the boost
## already is. Level 0 prices the first level bought.
##
## Priced off the total level rather than off a tier's own counter, which is what
## keeps the ladder one curve. The counter restarting is what made every boundary
## a discount of cost_growth^LEVELS_PER_TIER - and a boundary is also where the
## payout jumps, so the player was paid to cross into the tier worth more. It is
## also what leaves cost_growth_exponent nothing coherent to bend: an exponent
## raised through a level that resets bends the same short stretch of curve once
## per tier instead of bending the ladder once, end to end.
##
## BigNumber rather than float because it has to be - any exponent above 1.0 puts
## the top of this ladder past what a float holds, and pow_float saturates at
## BigNumber.MAX_EXPONENT rather than handing back an inf that spreads.
func cost_at(level: int) -> BigNumber:
	var steps := float(level) * pow(cost_growth_exponent, float(level))
	var tier := BoostTiers.tier_for_level(level)
	return BigNumber.from_value(base_cost) \
		.mul(BigNumber.from_value(cost_growth).pow_float(steps)) \
		.mul(BigNumber.from_value(tier_cost_growth).pow_float(float(tier - 1))) \
		.floored()
