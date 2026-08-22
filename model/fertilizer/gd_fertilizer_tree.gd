class_name FertilizerTree
extends RefCounted
## MODEL: expands the authored FertilizerUpgradeDefs into the UpgradeDefs the
## fertilizer UpgradeSystem actually holds levels for - one def per upgrade, with
## one effect per producer it names.
##
## Same shape as GrowthTree.build() / BoostTree.build() / ProjectTree.build(): the
## authored data describes the upgrade, and the defs are derived rather than
## hand-written, so adding one is a single .tres.
##
## Unlike GrowthTree's, these defs *are* priced. Fertilizer is a currency on
## PlayerData like any other, so they are bought through UpgradeSystem.buy() and
## cost() is read on them - base_cost and cost_growth carry the doubling ladder.

static func build(list: FertilizerUpgradeList, producers: GrowthProducerList) -> Array[UpgradeDef]:
	var defs: Array[UpgradeDef] = []
	if list == null:
		return defs
	var by_currency := _producers_by_currency(producers)
	for upgrade in list.upgrades:
		if upgrade == null:
			push_error("FertilizerUpgradeList holds a null entry, skipping it.")
			continue
		var effects: Array[UpgradeEffectDef] = []
		for currency in upgrade.currencies:
			if currency == null:
				push_error("FertilizerUpgradeDef '%s' names a null currency, skipping it." % upgrade.id)
				continue
			var producer: GrowthProducerDef = by_currency.get(currency.currency_type)
			if producer == null:
				push_error("FertilizerUpgradeDef '%s' names currency %d, which no growth producer covers, skipping it."
					% [upgrade.id, currency.currency_type])
				continue
			effects.append(_effect(producer, upgrade.per_level))
		if effects.is_empty():
			push_error("FertilizerUpgradeDef '%s' produced no effects, skipping it." % upgrade.id)
			continue
		defs.append(_build_def(upgrade, effects))
	return defs

## The producers indexed by the currency they make, so an upgrade naming a
## currency can pick up that producer's stat, scope and target.
static func _producers_by_currency(producers: GrowthProducerList) -> Dictionary:
	var by_currency: Dictionary = {}
	if producers == null:
		return by_currency
	for producer in producers.producers:
		if producer == null or producer.currency == null:
			continue
		by_currency[producer.currency.currency_type] = producer
	return by_currency

## One producer's share of a fertilizer upgrade: MORE + LINEAR, so n levels
## resolve as exactly 1 + per_level*n.
##
## Op.INCREASED would be the wrong shape for the reason GrowthTree._build_stack
## documents: it pools into the shared `inc` bucket alongside every symbiosis and
## biome upgrade writing the same stat, where each level is worth less than the
## one before. MORE keeps this ladder's own multiplier whole and independent.
##
## Carries the producer's own scope and target rather than a global one, which is
## what stops a &"node_production" bonus being applied once per node tier - see
## GrowthProducerDef.scope.
static func _effect(producer: GrowthProducerDef, per_level: float) -> UpgradeEffectDef:
	var effect := UpgradeEffectDef.new()
	effect.stat = producer.stat
	effect.op = UpgradeEffectDef.Op.MORE
	effect.scope = producer.scope
	effect.target = producer.target
	effect.per_level = per_level
	effect.level_scaling = UpgradeEffectDef.LevelScaling.LINEAR
	return effect

static func _build_def(upgrade: FertilizerUpgradeDef, effects: Array[UpgradeEffectDef]) -> UpgradeDef:
	var def := UpgradeDef.new()
	def.id = upgrade.id
	def.display_name = upgrade.display_name
	def.description = upgrade.description
	def.max_level = 0
	def.base_cost = BigNumber.from_value(upgrade.base_cost)
	def.cost_growth = upgrade.cost_growth
	def.cost_growth_exponent = 1.0
	def.effects = effects
	return def
