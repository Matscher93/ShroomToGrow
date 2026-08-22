class_name MissionBoostTree
extends RefCounted
## MODEL: expands the authored MissionBoostDefs into the UpgradeDefs the mission
## UpgradeSystem actually holds levels for - one def per authored boost.
##
## Same shape as FertilizerTree.build() / BoostTree.build() / ProjectTree.build():
## the authored data describes the rung, and the def is derived rather than
## hand-written, so a boost on a new stat is a single .tres.
##
## The effects are carried across untouched. That is the whole reason a general
## boost needs no wiring: a rung naming &"node_production" reaches the colony and
## one naming &"mission_speed" reaches the board, through the same ProductionSystem
## stack, without this file knowing the difference.

static func build(list: MissionBoostList) -> Array[UpgradeDef]:
	var defs: Array[UpgradeDef] = []
	if list == null:
		return defs
	for boost in list.boosts:
		if boost == null:
			push_error("MissionBoostList holds a null entry, skipping it.")
			continue
		if boost.effects.is_empty():
			push_error("MissionBoostDef '%s' has no effects, skipping it." % boost.id)
			continue
		defs.append(_build_def(boost))
	return defs

static func _build_def(boost: MissionBoostDef) -> UpgradeDef:
	var def := UpgradeDef.new()
	def.id = boost.id
	def.display_name = boost.display_name
	def.description = boost.description
	def.max_level = boost.max_level
	def.base_cost = boost.base_cost
	def.cost_growth = boost.cost_growth
	def.cost_growth_exponent = 1.0
	def.effects = boost.effects
	return def
