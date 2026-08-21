class_name GrowthTree
extends RefCounted
## MODEL: expands the authored GrowthProducerDefs into the UpgradeDefs the growth
## UpgradeSystem actually holds levels for - one invest def and one daily def per
## producer, plus the single global-doubling def they all share.
##
## Same shape as BoostTree.build() and ProjectTree.build(): the authored data
## describes the producer, and the defs are derived rather than hand-written, so
## adding a producer is one .tres rather than three.
##
## None of these defs is ever priced. Both stacks are bought through
## UpgradeSystem.buy_with_points() - a Level Point for an investment, the day's
## claim for a daily - so cost() is never read on them, and base_cost is zeroed
## rather than left at the class default that would imply otherwise.

## The one def carrying the doubling, with one effect per producer. A single def
## rather than one per producer so there is a single level to keep in step with
## the LP total: PlayerLevelSystem.sync_global_double() owns it.
const GLOBAL_DOUBLE_ID := &"lp_global_double"

## Level Points invested into one producer.
static func invest_id(currency: CurrencyTypes.Types) -> StringName:
	return StringName("lp_%s" % CurrencyTypes.field_for(currency))

## Daily rewards claimed into one producer.
static func daily_id(currency: CurrencyTypes.Types) -> StringName:
	return StringName("daily_%s" % CurrencyTypes.field_for(currency))

static func build(list: GrowthProducerList) -> Array[UpgradeDef]:
	var defs: Array[UpgradeDef] = []
	if list == null:
		return defs
	var double_effects: Array[UpgradeEffectDef] = []
	for producer in list.producers:
		if producer == null or producer.currency == null:
			push_error("GrowthProducerDef without a currency, skipping it.")
			continue
		var currency := producer.currency.currency_type
		var label := producer.currency.currency_name
		defs.append(_build_stack(producer, invest_id(currency),
			"%s Investment" % label,
			"Level Points invested here raise %s output." % label.to_lower(),
			producer.lp_per_level))
		defs.append(_build_stack(producer, daily_id(currency),
			"%s Daily Boost" % label,
			"Daily rewards claimed here raise %s output, permanently." % label.to_lower(),
			producer.daily_per_level))
		double_effects.append(_double_effect(producer))
	if not double_effects.is_empty():
		defs.append(_build_double(double_effects))
	return defs

## One additive stack ladder: MORE + LINEAR, so n levels resolve as exactly
## 1 + per_level*n.
##
## Op.INCREASED would be the wrong shape even though it reads like the additive
## one: it pools into the shared `inc` bucket alongside every symbiosis and biome
## upgrade writing the same stat, where each level is worth less than the one
## before. MORE keeps this ladder's own multiplier whole and independent.
static func _build_stack(producer: GrowthProducerDef, id: StringName, display_name: String,
		description: String, per_level: float) -> UpgradeDef:
	var effect := UpgradeEffectDef.new()
	effect.stat = producer.stat
	effect.op = UpgradeEffectDef.Op.MORE
	effect.scope = producer.scope
	effect.target = producer.target
	effect.per_level = per_level
	effect.level_scaling = UpgradeEffectDef.LevelScaling.LINEAR

	var effects: Array[UpgradeEffectDef] = [effect]
	var def := UpgradeDef.new()
	def.id = id
	def.display_name = display_name
	def.description = description
	def.max_level = 0
	def.base_cost = BigNumber.new(0.0, 0)
	def.cost_growth = 1.0
	def.effects = effects
	return def

## One producer's share of the doubling: MORE + COMPOUND at a per_level of 1.0,
## whose magnitude at level d is (1+1)^d - 1, so the effect multiplies by 2^d.
##
## Carries the producer's own scope and target, not a global one, for the reason
## GrowthProducerDef.scope documents - a global &"node_production" doubling would
## be applied once per node tier.
static func _double_effect(producer: GrowthProducerDef) -> UpgradeEffectDef:
	var effect := UpgradeEffectDef.new()
	effect.stat = producer.stat
	effect.op = UpgradeEffectDef.Op.MORE
	effect.scope = producer.scope
	effect.target = producer.target
	effect.per_level = 1.0
	effect.level_scaling = UpgradeEffectDef.LevelScaling.COMPOUND
	return effect

static func _build_double(effects: Array[UpgradeEffectDef]) -> UpgradeDef:
	var def := UpgradeDef.new()
	def.id = GLOBAL_DOUBLE_ID
	def.display_name = "Deep Roots"
	def.description = "Every ten Level Points invested, wherever they went, doubles every producer again."
	def.max_level = 0
	def.base_cost = BigNumber.new(0.0, 0)
	def.cost_growth = 1.0
	def.effects = effects
	return def
