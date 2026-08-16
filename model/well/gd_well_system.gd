class_name WellSystem
extends RefCounted
## MODEL: the well's economy - what funding a project costs in water, which of
## its boons are open, and what a funding buys.
##
## Projects are priced in water directly, the way boosts are priced in crystals:
## the cost curve authored on a ProjectDef is already the water price.
##
## Holds only its inputs, no App reference, so it can be built and exercised in
## isolation. Project levels live in a plain UpgradeSystem (one def per project
## per boon, built by ProjectTree), which is what makes a boon stack through
## ProductionSystem without any per-stat wiring here. That system is never reset:
## water is a run currency the sporation wipes, but what it was spent on is
## permanent.
##
## Later projects open on how far the well has been funded overall, not on
## anything bought elsewhere, so the whole ladder is reachable by a player who
## has found the lake and never sporated again.

var _player_data: PlayerData
var _upgrades: UpgradeSystem
var _projects: Array[ProjectDef] = []
var _by_id: Dictionary = {}   # StringName -> ProjectDef
var _list: ProjectList
## Levels of the perk that raises every project's ceiling. Read-only from here:
## perks are bought with biomass through PerkSystem, never with water. Nothing
## else about the Well touches the prestige track - which project is *open* is
## decided by the Well's own progress alone.
var _prestige_upgrades: UpgradeSystem

func _init(player_data: PlayerData, upgrades: UpgradeSystem, list: ProjectList,
		prestige_upgrades: UpgradeSystem = null) -> void:
	_player_data = player_data
	_upgrades = upgrades
	_list = list
	_prestige_upgrades = prestige_upgrades if prestige_upgrades != null else UpgradeSystem.new()
	if list != null:
		_projects = list.projects
	for project in _projects:
		_by_id[project.id] = project

# ---------------------------------------------------------------- lookup

func projects() -> Array[ProjectDef]:
	return _projects

func project_def(project_id: StringName) -> ProjectDef:
	return _by_id.get(project_id)

## Times this project has been funded. The first boon's def is the counter: it is
## the only one bought with water, so its level is the project's.
func level(project_id: StringName) -> int:
	return _upgrades.level(ProjectTree.upgrade_id(project_id, 0))

## How far this project may currently be funded: its authored ceiling plus
## whatever the depth perk has added. An uncapped project (max_level 0) stays
## uncapped - there is nothing for a perk to raise.
func max_level(project_id: StringName) -> int:
	var def: ProjectDef = _by_id.get(project_id)
	if def == null or def.max_level <= 0:
		return 0
	return def.max_level + extra_levels()

## Levels the depth perk currently adds to every project. Zero before it is
## bought, and zero for a list that authors no perk at all.
func extra_levels() -> int:
	if _list == null or _list.max_level_perk_id.is_empty():
		return 0
	return _list.max_level_per_perk_level * _prestige_upgrades.level(_list.max_level_perk_id)

func is_maxed(project_id: StringName) -> bool:
	var ceiling := max_level(project_id)
	return ceiling > 0 and level(project_id) >= ceiling

## False while the well has not been funded enough overall to open this project.
## Only blocks funding: levels bought before a threshold moved keep paying out.
##
## Measured off total_levels() rather than PlayerData's cached copy, so a gate
## can never be read from a projection that a save load has not re-synced yet.
func is_unlocked(project_id: StringName) -> bool:
	var def: ProjectDef = _by_id.get(project_id)
	if def == null:
		return false
	return total_levels() >= def.min_project_levels

## Fundings still owed before this project opens. Zero once it has.
func levels_until_unlock(project_id: StringName) -> int:
	var def: ProjectDef = _by_id.get(project_id)
	if def == null:
		return 0
	return maxi(0, def.min_project_levels - total_levels())

func min_project_levels(project_id: StringName) -> int:
	var def: ProjectDef = _by_id.get(project_id)
	return def.min_project_levels if def != null else 0

# ---------------------------------------------------------------- boons

## Boons of this project, in ladder order. Empty for an unknown id.
func boons(project_id: StringName) -> Array[ProjectBoonDef]:
	var def: ProjectDef = _by_id.get(project_id)
	if def == null:
		return []
	return def.boons

## True once the project has been funded far enough for this boon to pay out.
func is_boon_unlocked(project_id: StringName, index: int) -> bool:
	var def: ProjectDef = _by_id.get(project_id)
	if def == null or index < 0 or index >= def.boons.size():
		return false
	return level(project_id) >= def.boons[index].unlock_at_level

## Levels this boon itself has taken, which is how far past its threshold the
## project has been funded rather than how far it has been funded overall.
func boon_level(project_id: StringName, index: int) -> int:
	return _upgrades.level(ProjectTree.upgrade_id(project_id, index))

## What this boon currently contributes, resolved through the same effect
## machinery that pays it out, so the number shown is the number applied.
func boon_amount(project_id: StringName, index: int, ctx: ResolveContext) -> BigNumber:
	return _upgrades.effect_amount(ProjectTree.upgrade_id(project_id, index), ctx)

## What one more funding adds to this boon, at its current level. Not the same as
## the authored per_level for a COMPOUND boon, where each level is worth more
## than the one before it.
func boon_next_level_delta(project_id: StringName, index: int,
		ctx: ResolveContext) -> BigNumber:
	return _upgrades.next_level_delta(ProjectTree.upgrade_id(project_id, index), ctx)

# ---------------------------------------------------------------- funding

## Water the next funding costs. Zero once maxed, which is also what
## can_invest() reports on.
func cost(project_id: StringName) -> BigNumber:
	if is_maxed(project_id):
		return BigNumber.new(0.0, 0)
	return _upgrades.cost(ProjectTree.upgrade_id(project_id, 0))

func can_invest(project_id: StringName) -> bool:
	if not _by_id.has(project_id) or is_maxed(project_id) or not is_unlocked(project_id):
		return false
	return _player_data.water.gte(cost(project_id))

## Funds the project once: pays the water, raises its level, and takes a level on
## every boon the new level has opened.
##
## Batched because one funding moves several defs at once and every
## upgrades_changed listener (tick duration, the project cards, the biome level
## reading well_project_levels) refreshes synchronously. The player pressed one
## button, so they get one refresh.
func invest(project_id: StringName) -> bool:
	if not can_invest(project_id):
		return false
	_upgrades.begin_batch()
	var bought := _upgrades.buy(ProjectTree.upgrade_id(project_id, 0), _player_data, &"water")
	if bought:
		var lvl := level(project_id)
		var def: ProjectDef = _by_id[project_id]
		for i in range(1, def.boons.size()):
			if def.boons[i].unlock_at_level <= lvl:
				_upgrades.buy_with_points(ProjectTree.upgrade_id(project_id, i), true)
		sync_project_levels()
	_upgrades.end_batch()
	return bought

# ---------------------------------------------------------------- projection

## Total fundings across every project, the Underground Lake's XP source.
func total_levels() -> int:
	var total := 0
	for project in _projects:
		total += level(project.id)
	return total

## Rewrites PlayerData's cached copy of the above. Called after every funding and
## again after a save load, the same way AchievementSystem.sync_tier_count() is.
func sync_project_levels() -> void:
	_player_data.well_project_levels = total_levels()
