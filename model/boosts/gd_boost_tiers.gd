class_name BoostTiers
extends RefCounted
## MODEL: the boost ladder's fixed numbers, in one place.
##
## What changes every LEVELS_PER_TIER levels is how much a level of that boost is
## worth and what it costs.
##
## Both of those curves are authored per boost (see BoostDef.per_level and
## cost_at). What lives here is only what every boost shares: how tall a tier is.
##
## There is no last tier. A tier is just how many whole LEVELS_PER_TIER blocks sit
## behind a level, so the ladder keeps tiering for as long as a boost's ceiling
## keeps rising - which is what the perks and the Well's projects do to it.
##
## Levels multiply rather than add: a boost at level n of one tier is worth
## (1 + per_level)^n, so a hundred levels of a tier is worth its per-level rate
## compounded a hundred times, and the tier bump on top of that is what makes
## crossing a boundary matter.
##
## Both the system and the display side read this one table rather than each
## carrying its own copy of the curve.

## How tall one tier is, seeded once from the authored BoostList before any tier
## def is built - see configure(). A static var rather than a const so the shape is
## data the balance editor can write; still spelled as a constant because nothing
## may move it after configure() has run.
static var LEVELS_PER_TIER := 100

## Reads the ladder's shape off the authored list. Must run before any tier def is
## built: LEVELS_PER_TIER decides where the boundaries fall, and it is baked into
## every level's price.
##
## Null is a no-op rather than a reset, so a suite that builds systems without a
## list keeps the authored default instead of silently getting someone else's.
static func configure(list: BoostList) -> void:
	if list == null:
		return
	LEVELS_PER_TIER = maxi(1, list.levels_per_tier)

## Tier the *next* level falls into at this total level. Unbounded upwards: level
## 0 is tier 1 and every LEVELS_PER_TIER after it is one tier more, for as long as
## the boost's ceiling keeps being raised.
##
## It used to clamp at a last tier, which meant every level a perk opened past the
## ladder's end piled into the top tier - bought at that tier's rate and priced at
## it, however far past the end it really was.
static func tier_for_level(level: int) -> int:
	@warning_ignore("integer_division")
	return maxi(level, 0) / LEVELS_PER_TIER + 1

## Id of the UpgradeDef holding one boost's levels within one tier. Every tier is
## its own level counter, which is how the cost curve restarts at each boundary
## and how a level knows which per_level rate it was bought at.
static func upgrade_id(boost_id: StringName, tier: int) -> StringName:
	return StringName("%s_t%d" % [boost_id, tier])
