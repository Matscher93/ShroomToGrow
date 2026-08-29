class_name ExpeditionRewardTree
extends RefCounted
## MODEL: expands the authored expedition rewards into the UpgradeDefs the
## expedition UpgradeSystem holds levels for - one def per expedition that grants
## one.
##
## Same shape as MissionBoostTree.build() / BoostTree.build(): the authored data
## describes the reward, and the def is derived rather than hand-written.
##
## The difference from every other tree is that these levels are never bought.
## There is no cost curve here at all - max_level is 1, and MissionSystem grants
## that level when the expedition is collected. What the player spends is the
## expedition itself, which can only be run once.
##
## The effects are carried across untouched, which is the whole reason an
## expedition can pay in anything the game already resolves: a reward naming
## &"node_production" reaches the colony and one naming &"mission_speed" reaches
## the board, through the same ProductionSystem stack, without this file knowing
## the difference.

static func build(list: MissionList) -> Array[UpgradeDef]:
	var defs: Array[UpgradeDef] = []
	if list == null:
		return defs
	for mission in list.missions:
		if mission == null:
			push_error("MissionList holds a null entry, skipping it.")
			continue
		if mission.rewards.is_empty():
			continue
		# A farm loops, so a reward on one would be granted over and over. The
		# authored data is the mistake, not the load, so this says so and drops it
		# rather than registering a def that could be granted twice.
		if mission.is_farm:
			push_error("Farm '%s' carries rewards, which only expeditions grant. Skipping them."
				% mission.id)
			continue
		defs.append(_build_def(mission))
	return defs

static func _build_def(mission: MissionDef) -> UpgradeDef:
	var def := UpgradeDef.new()
	def.id = mission.id
	def.display_name = mission.display_name
	def.description = mission.description
	def.max_level = 1
	def.effects = mission.rewards
	return def
