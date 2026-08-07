class_name GeodeBoostTree
extends RefCounted
## MODEL: expands the authored GeodeBoostDefs into the UpgradeDefs the geode
## UpgradeSystem actually holds levels for - one def per (boost, tier).
##
## Same shape as PerkTree.build(): the authored data describes the boost, and
## the per-tier defs are derived rather than hand-written, so the ladder's shape
## lives in GeodeTiers alone and adding a tier is a constant change instead of
## ten more .tres files.

## One UpgradeDef per boost per tier, ready to register. Ids come from
## GeodeTiers.upgrade_id(), which is also what GeodeSystem looks levels up by.
static func build(list: GeodeBoostList) -> Array[UpgradeDef]:
	var defs: Array[UpgradeDef] = []
	if list == null:
		return defs
	for boost in list.boosts:
		for tier in range(1, GeodeTiers.MAX_TIER + 1):
			defs.append(_build_tier(boost, tier))
	return defs

static func _build_tier(boost: GeodeBoostDef, tier: int) -> UpgradeDef:
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
	def.id = GeodeTiers.upgrade_id(boost.id, tier)
	def.display_name = "%s (T%d)" % [boost.display_name, tier]
	def.description = boost.description
	def.max_level = GeodeTiers.LEVELS_PER_TIER
	# Each tier restarts the within-tier curve, but from a higher opening price
	# than the tier below - see GeodeBoostDef.tier_cost_growth.
	def.base_cost = BigNumber.from_value(boost.tier_base_cost(tier))
	def.cost_growth = boost.cost_growth
	def.effects = effects
	return def
