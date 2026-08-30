class_name BoostTree
extends RefCounted
## MODEL: expands the authored BoostDefs into the UpgradeDefs the boost
## UpgradeSystem actually holds levels for - one def per (boost, tier).
##
## Same shape as PerkTree.build(): the authored data describes the boost, and
## the per-tier defs are derived rather than hand-written, so the ladder's shape
## lives in BoostTiers alone and adding a tier is a constant change instead of
## ten more .tres files.
##
## Built a tier at a time rather than a whole ladder at once, because there is no
## last tier to stop at. BoostSystem grows a boost's defs as its ceiling rises -
## see BoostSystem._ensure_tier().

## One UpgradeDef per boost, for tiers 1..tiers. Ids come from
## BoostTiers.upgrade_id(), which is also what BoostSystem looks levels up by.
static func build(list: BoostList, tiers: int) -> Array[UpgradeDef]:
	var defs: Array[UpgradeDef] = []
	if list == null:
		return defs
	for boost in list.boosts:
		for tier in range(1, tiers + 1):
			defs.append(build_tier(boost, tier))
	return defs

## One boost's def for one tier. Public because the ladder is open-ended: the
## system builds the tier it is about to need rather than a fixed table.
static func build_tier(boost: BoostDef, tier: int) -> UpgradeDef:
	# MORE + COMPOUND is what makes a boost level multiply rather than add: the
	# effect's magnitude at level n is (1 + per_level)^n - 1, and a MORE effect
	# multiplies base by one plus that, i.e. (1 + per_level)^n. INCREASED, or
	# LINEAR scaling, would drop it back into the additive pool the symbiosis and
	# biome upgrades share, where each level is worth less than the one before.
	var effect := UpgradeEffectDef.new()
	effect.stat = boost.stat
	effect.op = UpgradeEffectDef.Op.MORE
	effect.scope = boost.scope
	effect.target = boost.target
	effect.per_level = boost.per_level(tier)
	effect.level_scaling = UpgradeEffectDef.LevelScaling.COMPOUND

	var effects: Array[UpgradeEffectDef] = [effect]
	var def := UpgradeDef.new()
	def.id = BoostTiers.upgrade_id(boost.id, tier)
	def.display_name = "%s (T%d)" % [boost.display_name, tier]
	def.description = boost.description
	# Deliberately uncapped, however tall a tier nominally is: a &"boost_max_level"
	# upgrade can push the ladder past its last tier, and every level past it is
	# bought into the top tier's counter. BoostSystem.is_maxed() owns the ceiling,
	# because it is the only thing that knows where the ceiling currently is.
	def.max_level = 0
	# Deliberately unpriced. These defs are level counters and effect carriers;
	# what a level costs is BoostSystem.boost_cost(), off BoostDef.cost_at() and
	# the total level across every tier.
	#
	# A price here could only ever be a per-tier one, and a per-tier price is
	# what made a boundary a discount - it cannot see the levels below it, so it
	# restarts the curve and has nothing for cost_growth_exponent to bend. Left
	# at the UpgradeDef defaults rather than filled in with a number no caller
	# reads, which would drift out of step with the real curve unnoticed.
	def.effects = effects
	return def
