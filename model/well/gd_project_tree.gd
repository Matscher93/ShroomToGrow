class_name ProjectTree
extends RefCounted
## MODEL: expands the authored ProjectDefs into the UpgradeDefs the project
## UpgradeSystem actually holds levels for - one def per (project, boon).
##
## Same shape as BoostTree.build() / PerkTree.build(): the authored data
## describes the project, and the per-boon defs are derived, so a boon on a new
## stat is a .tres edit and nothing else.
##
## Only the first boon's def is ever bought with water. The rest are levelled
## with buy_with_points() by WellSystem the moment the project reaches their
## threshold, which is what makes a boon's own level count from where it opened
## rather than from where the project started.

## One UpgradeDef per project per boon, ready to register. Ids come from
## upgrade_id(), which is also what WellSystem looks levels up by.
static func build(list: ProjectList) -> Array[UpgradeDef]:
	var defs: Array[UpgradeDef] = []
	if list == null:
		return defs
	for project in list.projects:
		for i in project.boons.size():
			defs.append(_build_boon(project, i))
	return defs

## Id of the UpgradeDef holding one project's levels for one of its boons. Index
## 0 is the project's own counter and price; every other index is a payoff that
## rides along with it.
static func upgrade_id(project_id: StringName, index: int) -> StringName:
	return StringName("%s_b%d" % [project_id, index])

static func _build_boon(project: ProjectDef, index: int) -> UpgradeDef:
	var boon := project.boons[index]
	var effects: Array[UpgradeEffectDef] = []
	if boon.effect != null:
		effects.append(boon.effect)

	var def := UpgradeDef.new()
	def.id = upgrade_id(project.id, index)
	def.display_name = "%s - %s" % [project.display_name, boon.display_name]
	def.description = boon.description
	def.effects = effects
	# Deliberately uncapped, however far the project itself may be funded:
	# WellSystem.max_level() moves with the depth perk, and a ceiling baked in
	# here would be a second, static answer to the same question - one that
	# refused the very levels the perk was bought to allow.
	#
	# Nothing is lost by leaving it open. A boon only ever takes a level when
	# WellSystem.invest() gives it one, and that happens once per funding of a
	# project whose own ceiling can_invest() already enforces, so boon k settles
	# at (project level - unlock_at_level + 1) on its own.
	def.max_level = 0
	# Only boon 0 is ever bought with water, so it is the only one whose cost
	# curve means anything. The rest keep the UpgradeDef defaults, which
	# buy_with_points() never reads.
	if index == 0:
		def.base_cost = project.base_cost
		def.cost_growth = project.cost_growth
		def.cost_growth_exponent = project.cost_growth_exponent
	return def
