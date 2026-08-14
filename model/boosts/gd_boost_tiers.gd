class_name BoostTiers
extends RefCounted
## MODEL: the boost ladder's fixed numbers, in one place.
##
## What changes every LEVELS_PER_TIER levels is how much a level of that boost is
## worth and what it costs.
##
## Both of those curves are authored per boost (see BoostDef.per_level and
## tier_base_cost). What lives here is only what every boost shares: how tall a
## tier is and how many there are.
##
## Levels multiply rather than add: a boost at level n of one tier is worth
## (1 + per_level)^n, so a hundred levels of a tier is worth its per-level rate
## compounded a hundred times, and the tier bump on top of that is what makes
## crossing a boundary matter.
##
## Holds no state, so both the system and the display side read the same table
## rather than each carrying its own copy of the curve.

const MAX_TIER := 5
const LEVELS_PER_TIER := 100

## Highest boost level the ladder can reach, i.e. every tier maxed.
static func max_level() -> int:
	return MAX_TIER * LEVELS_PER_TIER

## Tier the *next* level falls into at this total level. Clamped at MAX_TIER so a
## maxed ladder still reports a real tier rather than one past the end of the
## table.
static func tier_for_level(level: int) -> int:
	return clampi(level / LEVELS_PER_TIER + 1, 1, MAX_TIER)

## Id of the UpgradeDef holding one boost's levels within one tier. Every tier is
## its own level counter, which is how the cost curve restarts at each boundary
## and how a level knows which per_level rate it was bought at.
static func upgrade_id(boost_id: StringName, tier: int) -> StringName:
	return StringName("%s_t%d" % [boost_id, tier])
