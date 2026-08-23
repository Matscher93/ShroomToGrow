extends Node
## AUTOLOAD "App": the composition root.
## Owns the Models and ViewModels for the app's lifetime.
## Register in Project Settings > Autoload as "App".
##
## Models and VMs are RefCounted, so this autoload's references keep them alive.
## Views come and go with the scene tree.

signal biome_size_changed(key: StringName)

var player_data: PlayerData
var player_vm: PlayerViewModel
var mycelium_node_data: Array[MyceliumNodeData]
var mycelium_node_vms: Array[MyceliumNodeViewModel]
var nodes := load("res://data/mycelium_nodes/res_all_mycelium_nodes.tres") as MyceliumNodes
var screens_data: ScreensData
var screens_vm: ScreensViewModel
var navigation_vm: NavigationViewModel
var screens := load("res://data/screens/all_screens.tres") as Screens

var offline_income_vm: OfflineIncomeViewModel
var tick_timer: Timer
## Drives event spawns. Wall clock rather than the tick, and one_shot rather than
## repeating, because each interval is drawn fresh - see EventSystem for why the
## cadence is the player's rather than the game's.
var event_timer: Timer

var upgrade_system: UpgradeSystem
var prestige_upgrade_system: UpgradeSystem
var biome_upgrade_system: UpgradeSystem
## Levels of the two crystal boosts, one UpgradeDef per boost per tier. A track of
## its own rather than a corner of the prestige one: boosts are permanent, the
## defs are generated from BoostTiers instead of authored, and it saves and
## resets on its own terms.
var boost_upgrade_system: UpgradeSystem
## Levels of the well's projects, one UpgradeDef per project per boon. Its own
## track for the same reasons the boosts have one: the defs are generated from
## ProjectTree rather than authored, and it is permanent - the sporation wipes
## the water but never what the water was spent on.
var project_upgrade_system: UpgradeSystem
## Levels of the player-level investments and the daily-reward stacks, one
## UpgradeDef per producer per kind plus the shared doubling. Its own track for
## the same reasons the boosts and projects have one: the defs are generated from
## GrowthTree rather than authored, and it is permanent - both halves of it are
## account progress the sporation has no claim on.
var growth_upgrade_system: UpgradeSystem
## Levels of the three fertilizer upgrades, one UpgradeDef per upgrade. Its own
## track for the same reasons the boosts, projects and growth have one: the defs
## are generated from FertilizerTree rather than authored, and it is permanent -
## fertilizer is earned from events and the sporation has no claim on it.
var fertilizer_upgrade_system: UpgradeSystem
## Levels of the Ruins boost ladder, one UpgradeDef per authored rung. Its own
## track for the same reasons the boosts, projects and growth have one: the defs
## are generated from MissionBoostTree rather than authored, and it is permanent -
## the mission currencies survive a sporation, and so does what they bought.
var mission_upgrade_system: UpgradeSystem
var resolve_context := ResolveContext.new()

## Game rules, split out by domain. Each is constructed with the state it needs
## and holds no reference back to App, so it can be built and exercised without
## the autoload existing. App keeps a delegating method per public entry point
## (bottom of this file) so ViewModels can keep binding to App.*.
var production_system: ProductionSystem
var biome_system: BiomeSystem
var perk_system: PerkSystem
var tick_system: TickSystem
var prestige_system: PrestigeSystem
var water_system: WaterSystem
var well_system: WellSystem
var player_level_system: PlayerLevelSystem
var daily_reward_system: DailyRewardSystem
var fertilizer_system: FertilizerSystem
var event_system: EventSystem
var creature_system: CreatureSystem
var mission_system: MissionSystem
var mission_boost_system: MissionBoostSystem

var biomes := load("res://data/biomes/all_biomes.tres") as BiomeList
var biomes_data: BiomesData
var biome_vms: Dictionary = {}  # StringName -> BiomeViewModel

var perk_branches := load("res://data/prestige/all_branches.tres") as PerkBranchList
var perk_defs: Dictionary = {}  # StringName -> PerkDef
var perk_vms: Dictionary = {}  # StringName -> PerkViewModel
var prestige_vm: PrestigeViewModel

var achievements := load("res://data/achievements/all_achievements.tres") as AchievementList
var achievement_progress: AchievementProgress
var achievement_system: AchievementSystem
var achievement_vms: Dictionary = {}  # StringName -> AchievementViewModel
var achievements_vm: AchievementsViewModel

var boosts := load("res://data/boosts/all_boosts.tres") as BoostList
var boost_system: BoostSystem
var boost_vms: Dictionary = {}  # StringName -> BoostViewModel

var projects := load("res://data/well/all_projects.tres") as ProjectList
var project_vms: Dictionary = {}  # StringName -> ProjectViewModel
var well_vm: WellViewModel

var growth_producers := load("res://data/growth/all_producers.tres") as GrowthProducerList
var daily_reward_data: DailyRewardData
var growth_vm: GrowthViewModel

var fertilizer_upgrades := load("res://data/fertilizer/all_fertilizer_upgrades.tres") as FertilizerUpgradeList
var random_events := load("res://data/events/all_random_events.tres") as RandomEventList
var events_data: EventsData
var events_vm: EventsViewModel

var creature_defs := load("res://data/ruins/all_creatures.tres") as CreatureList
var mission_defs := load("res://data/ruins/all_missions.tres") as MissionList
var mission_boosts := load("res://data/ruins/all_mission_boosts.tres") as MissionBoostList
var ruins_data: RuinsData
var creature_vms: Dictionary = {}       # StringName -> CreatureViewModel
var mission_vms: Dictionary = {}        # StringName -> MissionViewModel
var mission_boost_vms: Dictionary = {}  # StringName -> MissionBoostViewModel
var ruins_vm: RuinsViewModel

var automations := load("res://data/automation/all_automations.tres") as AutomationList
var automation_data: AutomationData
var automation_system: AutomationSystem
var automation_vms: Dictionary = {}  # StringName -> AutomationViewModel
var biome_sequence_vms: Dictionary = {}  # StringName (biome key) -> BiomeSequenceViewModel
var crystal_caves_vm: CrystalCavesViewModel

## Cleared by SaveManager for the duration of the offline catch-up. Automations
## are an active-play feature: the catch-up replays production only, and letting
## them buy through a night's worth of ticks in one burst is a different game.
var automations_running := true

## Cleared by SaveManager alongside automations_running, and for the same reason:
## events are an active-play feature. A night away would otherwise arrive as a
## full queue and several auto-completed progress quests, which pays the player
## for being absent.
var events_running := true

## Set by anything an achievement could measure, drained once per frame in
## _process. Evaluating per change would re-walk every achievement several times
## a tick, and the offline catch-up loop drives handle_tick() thousands of times
## in a row, so the flag collapses all of that into one evaluate per frame.
var _achievements_dirty := true

const BASE_TICK_DURATION := 10.0
const MIN_TICK_DURATION := 1.0  # floor so a stacked tick_rate discount can't reach zero

func _ready() -> void:
	player_data = PlayerData.new()
	player_vm = PlayerViewModel.new(player_data)

	upgrade_system = UpgradeSystem.new()
	for def in UpgradeDefLoader.load_all(UpgradeDefLoader.SYMBIOSIS_PATH):
		upgrade_system.register(def)

	prestige_upgrade_system = UpgradeSystem.new()
	for def in UpgradeDefLoader.load_all(UpgradeDefLoader.PRESTIGE_PATH):
		prestige_upgrade_system.register(def)

	biome_upgrade_system = UpgradeSystem.new()
	for def in UpgradeDefLoader.load_all(UpgradeDefLoader.BIOME_PATH):
		biome_upgrade_system.register(def)

	boost_upgrade_system = UpgradeSystem.new()
	for def in BoostTree.build(boosts):
		boost_upgrade_system.register(def)

	project_upgrade_system = UpgradeSystem.new()
	for def in ProjectTree.build(projects):
		project_upgrade_system.register(def)

	growth_upgrade_system = UpgradeSystem.new()
	for def in GrowthTree.build(growth_producers):
		growth_upgrade_system.register(def)

	# Built from the growth producers as well as its own list: a fertilizer
	# upgrade names the currencies it raises and picks up each one's stat, scope
	# and target from the producer that already describes it.
	fertilizer_upgrade_system = UpgradeSystem.new()
	for def in FertilizerTree.build(fertilizer_upgrades, growth_producers):
		fertilizer_upgrade_system.register(def)

	mission_upgrade_system = UpgradeSystem.new()
	for def in MissionBoostTree.build(mission_boosts):
		mission_upgrade_system.register(def)

	production_system = ProductionSystem.new(upgrade_system, biome_upgrade_system,
		prestige_upgrade_system, resolve_context, boost_upgrade_system,
		project_upgrade_system, growth_upgrade_system, fertilizer_upgrade_system,
		mission_upgrade_system)
	# Built before the tick system, which drives the pump: the well's rate and
	# yield are stats like any other, but whether it runs at all is a biome unlock.
	biomes_data = BiomesData.new()
	water_system = WaterSystem.new(player_data, biomes_data, production_system)
	tick_system = TickSystem.new(nodes.mycelium_nodes, player_data, production_system,
		water_system)

	for perk in PerkTree.build(perk_branches):
		prestige_upgrade_system.register(perk)
		perk_defs[perk.id] = perk
	perk_system = PerkSystem.new(perk_defs, prestige_upgrade_system, player_data)
	# Built after perk_system: PerkViewModel reads perk state through App, which
	# forwards to it, so it must exist before the first VM is constructed.
	for id in perk_defs:
		perk_vms[id] = PerkViewModel.new(id, perk_defs[id])
	prestige_vm = PrestigeViewModel.new()

	biome_system = BiomeSystem.new(biomes, biomes_data, player_data, nodes.mycelium_nodes,
		production_system, upgrade_system, biome_upgrade_system, prestige_upgrade_system,
		resolve_context)
	biome_system.unlock_free_biomes()
	for def in biomes.biomes:
		biome_vms[def.key] = BiomeViewModel.new(def.key, def)

	prestige_system = PrestigeSystem.new(player_data, biomes_data, nodes.mycelium_nodes,
		production_system, upgrade_system, biome_upgrade_system, biome_system)

	for node in nodes.mycelium_nodes:
		var mycelium_data := MyceliumNodeData.new(player_data, node, prestige_upgrade_system)
		mycelium_node_data.append(mycelium_data)
		mycelium_node_vms.append(MyceliumNodeViewModel.new(player_data, mycelium_data))
		_track_manual_count(node)

	achievement_progress = AchievementProgress.new()
	achievement_system = AchievementSystem.new(achievements, achievement_progress, player_data,
		production_system, upgrade_system, biomes_data)

	boost_system = BoostSystem.new(player_data, boost_upgrade_system, boosts,
		prestige_upgrade_system, production_system)

	well_system = WellSystem.new(player_data, project_upgrade_system, projects,
		prestige_upgrade_system)

	daily_reward_data = DailyRewardData.new()
	player_level_system = PlayerLevelSystem.new(player_data, growth_upgrade_system,
		growth_producers, production_system)
	daily_reward_system = DailyRewardSystem.new(daily_reward_data, growth_upgrade_system,
		growth_producers)

	# Built after biomes_data, which gates the crystal event, and before the VMs
	# that read them back through App.
	fertilizer_system = FertilizerSystem.new(player_data, fertilizer_upgrade_system,
		fertilizer_upgrades)
	events_data = EventsData.new()
	event_system = EventSystem.new(events_data, player_data, biomes_data,
		fertilizer_system, random_events)

	# The Ruins, in dependency order: the roster before the board that sends it
	# out, and the board before nothing - the boost ladder only reads the tally.
	# All three share one RuinsData, which is what lets CreatureSystem answer
	# "is this creature out right now" without knowing about missions.
	ruins_data = RuinsData.new()
	creature_system = CreatureSystem.new(ruins_data, player_data, creature_defs,
		production_system)
	mission_system = MissionSystem.new(ruins_data, player_data, biomes_data,
		production_system, creature_system, mission_defs, prestige_upgrade_system)
	mission_boost_system = MissionBoostSystem.new(player_data, mission_upgrade_system,
		ruins_data, mission_boosts)

	# A boost's per-level rate is baked into its UpgradeDef, and the Well's
	# projects move it. Funding one is the only thing that can, so the rebuild
	# rides that signal rather than a tick. Run once up front too: a save loaded
	# after this point re-fires it, but a fresh game never would.
	project_upgrade_system.upgrades_changed.connect(boost_system.refresh_power)
	boost_system.refresh_power()

	automation_data = AutomationData.new()
	automation_system = AutomationSystem.new(automations, automation_data, player_data,
		production_system, mycelium_node_data, upgrade_system, biomes, biomes_data,
		biome_system, prestige_upgrade_system)
	automation_system.biome_size_bought.connect(_on_automation_bought_size)

	# Built after their systems: the VMs read state back through App, which
	# forwards to them, so they must exist before the first VM is constructed.
	for def in achievements.achievements:
		achievement_vms[def.id] = AchievementViewModel.new(def)
	achievements_vm = AchievementsViewModel.new()
	for def in automations.automations:
		automation_vms[def.id] = AutomationViewModel.new(def)
	for def in biomes.biomes:
		biome_sequence_vms[def.key] = BiomeSequenceViewModel.new(def.key, def)
	for def in boosts.boosts:
		boost_vms[def.id] = BoostViewModel.new(def.id, def)
	for def in projects.projects:
		project_vms[def.id] = ProjectViewModel.new(def.id, def)
	for def in creature_defs.creatures:
		creature_vms[def.id] = CreatureViewModel.new(def.id, def)
	for def in mission_defs.missions:
		mission_vms[def.id] = MissionViewModel.new(def.id, def)
	for def in mission_boosts.boosts:
		mission_boost_vms[def.id] = MissionBoostViewModel.new(def.id, def)
	# Ahead of the screen VMs below: they subscribe to it in their constructors.
	screens_data = ScreensData.new(screens.screens, screens.initial_screen)
	# After boost_vms: the Caves screen's VM hands out those cards.
	crystal_caves_vm = CrystalCavesViewModel.new()
	# After project_vms, for the same reason.
	well_vm = WellViewModel.new()
	# After player_level_system, daily_reward_system and fertilizer_system: the
	# sheet holds all three sections and reads them back through App.
	growth_vm = GrowthViewModel.new()
	# After event_system, for the same reason.
	events_vm = EventsViewModel.new()
	# After the three Ruins VM dictionaries: the screen's VM hands out those cards.
	# Ahead of navigation_vm below, which reads it for the Ruins sub-rows.
	ruins_vm = RuinsViewModel.new()

	screens_vm = ScreensViewModel.new(screens_data)
	# After screens_data and crystal_caves_vm: the nav menu reads the screen
	# registry for its rows and the Caves VM for that screen's sub-rows.
	navigation_vm = NavigationViewModel.new()

	offline_income_vm = OfflineIncomeViewModel.new()

	tick_timer = Timer.new()
	tick_timer.wait_time = BASE_TICK_DURATION
	tick_timer.autostart = true
	tick_timer.timeout.connect(func() -> void:
		handle_tick()
	)
	add_child(tick_timer)

	# Deliberately not persisted: "active play only" means the countdown to the
	# next event starts fresh each session rather than banking up while away.
	event_timer = Timer.new()
	event_timer.one_shot = true
	event_timer.timeout.connect(_on_event_timer_timeout)
	add_child(event_timer)
	event_timer.start(event_system.next_interval())

	upgrade_system.upgrades_changed.connect(_update_tick_duration)
	biome_upgrade_system.upgrades_changed.connect(_update_tick_duration)
	prestige_upgrade_system.upgrades_changed.connect(_update_tick_duration)
	boost_upgrade_system.upgrades_changed.connect(_update_tick_duration)
	project_upgrade_system.upgrades_changed.connect(_update_tick_duration)
	# The mission track is here and the growth and fertilizer tracks are not:
	# those two only ever write the four producer stats, but a Ruins boost can
	# name &"tick_rate" like any biome upgrade, and Deep Time does.
	mission_upgrade_system.upgrades_changed.connect(_update_tick_duration)
	_update_tick_duration()

	_connect_achievement_sources()

## Puts one event on the board and arms the next interval. The timer is restarted
## either way: a spawn skipped because the queue is full or because a catch-up is
## running must not stop the clock, or events would never resume.
func _on_event_timer_timeout() -> void:
	if events_running:
		event_system.try_spawn()
	event_timer.start(event_system.next_interval())

## One evaluate per frame at most, and only when something actually moved. See
## _achievements_dirty.
func _process(_delta: float) -> void:
	if not _achievements_dirty:
		return
	_achievements_dirty = false
	achievement_system.evaluate()

func mark_achievements_dirty() -> void:
	_achievements_dirty = true

## Everything an AchievementDef.Stat can be derived from. A source missing here
## only delays the award to the next tick, never loses it, since handle_tick()
## sets the flag too.
func _connect_achievement_sources() -> void:
	for node in nodes.mycelium_nodes:
		node.manual_nodes_changed.connect(mark_achievements_dirty.unbind(1))
	upgrade_system.upgrades_changed.connect(mark_achievements_dirty)
	biome_upgrade_system.upgrades_changed.connect(mark_achievements_dirty)
	prestige_upgrade_system.upgrades_changed.connect(mark_achievements_dirty)
	boost_upgrade_system.upgrades_changed.connect(mark_achievements_dirty)
	project_upgrade_system.upgrades_changed.connect(mark_achievements_dirty)
	growth_upgrade_system.upgrades_changed.connect(mark_achievements_dirty)
	mission_upgrade_system.upgrades_changed.connect(mark_achievements_dirty)
	fertilizer_upgrade_system.upgrades_changed.connect(mark_achievements_dirty)
	biomes_data.biome_unlocked.connect(mark_achievements_dirty.unbind(1))
	player_data.prestige_count_changed.connect(mark_achievements_dirty.unbind(1))
	biome_size_changed.connect(mark_achievements_dirty.unbind(1))
	# Crystals move when an achievement is claimed, which is exactly when the
	# crystal-counting achievement can complete a tier. Without this its claim
	# button sat dead until the next tick happened to set the flag.
	player_data.crystals_changed.connect(mark_achievements_dirty.unbind(1))

# ---------------------------------------------------------------- automation

## Same contract as buy_biome_size below: views bind to App, not to the systems.
func _on_automation_bought_size(key: StringName) -> void:
	biome_size_changed.emit(key)

func _track_manual_count(node: MyceliumNode) -> void:
	var key := StringName("ManualNode%d" % node.node_id)
	resolve_context.manual_counts[key] = node.manual_nodes
	node.manual_nodes_changed.connect(func(value: int) -> void:
		resolve_context.manual_counts[key] = value
		upgrade_system.invalidate()
	)

## Timer.wait_time only takes hold on the timer's next cycle, so writing it alone
## leaves the cycle already in flight running at its old length. That is most
## visible at startup: the timer autostarts at BASE_TICK_DURATION while App is
## built, and SaveManager loads the save afterwards, so the first tick of a
## session would count down from 10s no matter what the save's tick_rate says.
##
## start() is the only way to move time_left, and it overwrites wait_time, hence
## the write after it - the setter leaves time_left alone, so the shortened cycle
## survives. Only ever shortens: a duration change never stretches the tick the
## player is already waiting on. Skipped while stopped so the offline catch-up,
## which stops the timer and drives handle_tick() itself, isn't restarted
## mid-loop.
func _update_tick_duration() -> void:
	var duration := tick_duration()
	if not tick_timer.is_stopped() and tick_timer.time_left > duration:
		tick_timer.start(duration)
	tick_timer.wait_time = duration

# ---------------------------------------------------------------- save state

## Everything a run consists of, in one dictionary.
##
## Lives here rather than in SaveManager because this is where the systems being
## serialised are: a track added to _ready() is a track this has to carry, and
## the two are one screen apart. SaveManager owns the file the dictionary goes
## into - the version, the timestamp, the backup - and the balance simulator
## reads and writes the same shape without a SaveManager at all, which is the
## other reason it cannot live in one.
func to_save() -> Dictionary:
	return {
		"player_data": player_data.to_save(),
		"mycelium_nodes": mycelium_nodes_to_save(),
		"upgrades": upgrade_system.to_save(),
		"prestige_upgrades": prestige_upgrade_system.to_save(),
		"biomes": biomes_data.to_save(),
		"biome_upgrades": biome_upgrade_system.to_save(),
		"achievements": achievement_progress.to_save(),
		"automation": automation_data.to_save(),
		"boost_upgrades": boost_upgrade_system.to_save(),
		"project_upgrades": project_upgrade_system.to_save(),
		"growth_upgrades": growth_upgrade_system.to_save(),
		"daily_reward": daily_reward_data.to_save(),
		"ruins": ruins_data.to_save(),
		"mission_upgrades": mission_upgrade_system.to_save(),
		"fertilizer_upgrades": fertilizer_upgrade_system.to_save(),
		"events": events_data.to_save(),
	}

## Loads a dictionary from to_save() into the live systems. Every holder is
## loaded through its own loader with whatever the save had, so a missing key
## leaves that track at its fresh-start values rather than failing the load.
func load_from_save(game: Dictionary) -> void:
	player_data.load_from_save(game.get("player_data", {}))
	mycelium_nodes_from_save(game.get("mycelium_nodes", {}))
	upgrade_system.from_save(game.get("upgrades", {}))
	prestige_upgrade_system.from_save(game.get("prestige_upgrades", {}))
	biomes_data.load_from_save(game.get("biomes", {}))
	resolve_context.biome_sizes = biomes_data.size.duplicate()
	biome_upgrade_system.from_save(game.get("biome_upgrades", {}))
	achievement_progress.load_from_save(game.get("achievements", {}))
	# PlayerData.achievement_tiers is a projection of the progress just loaded,
	# not a saved field, so it has to be rebuilt here.
	achievement_system.sync_tier_count()
	automation_data.load_from_save(game.get("automation", {}))
	boost_upgrade_system.from_save(game.get("boost_upgrades", {}))
	project_upgrade_system.from_save(game.get("project_upgrades", {}))
	# PlayerData.well_project_levels is a projection of the levels just loaded,
	# not a saved field, so it has to be rebuilt here - same as achievement_tiers.
	well_system.sync_project_levels()
	growth_upgrade_system.from_save(game.get("growth_upgrades", {}))
	# The doubling level does round-trip with the rest of the track, so this is a
	# drift guard rather than the primary path. See sync_global_double().
	player_level_system.sync_global_double()
	fertilizer_upgrade_system.from_save(game.get("fertilizer_upgrades", {}))
	events_data.load_from_save(game.get("events", {}))
	mission_upgrade_system.from_save(game.get("mission_upgrades", {}))
	ruins_data.load_from_save(game.get("ruins", {}))
	# PlayerData.missions_completed is a projection of the tally just loaded, not
	# a saved field, so it has to be rebuilt here - same as well_project_levels.
	mission_system.sync_missions_completed()
	# Only a device clock moved backwards can leave a mission's start in the
	# future, and only a load can be the first thing to notice.
	mission_system.sync_clock_rollback()
	daily_reward_data.load_from_save(game.get("daily_reward", {}))
	# Only a device clock moved backwards can leave a last-claim day in the
	# future, and only a load can be the first thing to notice.
	daily_reward_system.sync_clock_rollback()

## Keyed by node_id, like every other track in the file.
##
## It used to be a plain array read back by position, which meant inserting or
## reordering a tier in the authored list shifted every existing player's counts
## onto the wrong tiers - silently, with nothing to migrate against. The v8
## migration turns the old array into this shape by index, which is the only
## point at which position and id are still known to agree.
func mycelium_nodes_to_save() -> Dictionary:
	var all_node_data := {}
	for node_data in mycelium_node_data:
		all_node_data[str(node_data.node.node_id)] = {
			"manual_nodes": node_data.node.manual_nodes,
			"auto_nodes": node_data.node.auto_nodes.to_save(),
		}
	return all_node_data

## Entries that are not Dictionaries are skipped rather than assigned: the typed
## local below would take the whole load down on a corrupt save, which is the one
## path that has to degrade instead. A skipped tier keeps its fresh-start values,
## and so does a tier the save has no entry for at all.
func mycelium_nodes_from_save(saved_nodes: Dictionary) -> void:
	for node_data in mycelium_node_data:
		var key := str(node_data.node.node_id)
		if not saved_nodes.has(key):
			continue
		if not saved_nodes[key] is Dictionary:
			push_warning("Save entry for mycelium node %s is not a Dictionary, skipping it." % key)
			continue
		var loaded_data: Dictionary = saved_nodes[key]
		node_data.node.manual_nodes = loaded_data.get("manual_nodes", 0)
		node_data.node.auto_nodes = BigNumber.from_save(loaded_data.get("auto_nodes", {}))

# ---------------------------------------------------------------------------
# Delegators. The rules live in ProductionSystem / TickSystem / BiomeSystem /
# PerkSystem / PrestigeSystem, which hold no App reference and can be built
# standalone. These thin forwards keep App the single entry point the
# ViewModels bind to.
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------- tick

func node_production_bonuses() -> Array[BigNumber]:
	return tick_system.node_production_bonuses()

func handle_tick(bonuses: Array[BigNumber] = []) -> void:
	tick_system.handle_tick(bonuses)
	_achievements_dirty = true
	# Live ticks only. A progress quest measures time the player was here for, so
	# the offline catch-up must not walk one to its goal - same reason the spawn
	# timer checks this flag.
	if events_running:
		event_system.handle_tick()
	# After production, so an automation spends the nutrients this tick just
	# paid out rather than always working a tick behind.
	if automations_running:
		# Batched: one automation may buy many levels in this one call - the tick
		# is bounded by time, not by a level count - and every upgrades_changed
		# listener (tick duration, the biome panels' slot grids, every node card)
		# refreshes synchronously. The player sees one tick, so they get one
		# refresh.
		upgrade_system.begin_batch()
		biome_upgrade_system.begin_batch()
		prestige_upgrade_system.begin_batch()
		automation_system.handle_tick()
		prestige_upgrade_system.end_batch()
		biome_upgrade_system.end_batch()
		upgrade_system.end_batch()

# ---------------------------------------------------------------- production

func node_potency_bonus(node_id: StringName) -> BigNumber:
	return production_system.node_potency_bonus(node_id)

func node_synergy_bonus(node_id: StringName) -> BigNumber:
	return production_system.node_synergy_bonus(node_id)

func node_potency_external_multiplier(node_id: StringName) -> BigNumber:
	return production_system.node_potency_external_multiplier(node_id)

func node_synergy_external_multiplier(node_id: StringName) -> BigNumber:
	return production_system.node_synergy_external_multiplier(node_id)

func node_symbiosis_bonus(node_id: StringName) -> BigNumber:
	return production_system.node_symbiosis_bonus(node_id)

func node_production_bonus(node_id: StringName) -> BigNumber:
	return production_system.node_production_bonus(node_id)

func tick_duration() -> float:
	return production_system.tick_duration(BASE_TICK_DURATION, MIN_TICK_DURATION)

## Seconds left on the tick in flight. Reads off the live Timer, which is a Node,
## which is exactly why it is answered here: the resource bar used to hold
## App.tick_timer itself and a ViewModel cannot take that over without touching a
## node. Returns the full duration while the timer is stopped, which is what the
## offline catch-up leaves it in.
func tick_time_left() -> float:
	if tick_timer == null or tick_timer.is_stopped():
		return tick_duration()
	return tick_timer.time_left

# ---------------------------------------------------------------- prestige

func preview_biomass_gain() -> BigNumber:
	return prestige_system.preview_biomass_gain()

func can_prestige() -> bool:
	return prestige_system.can_prestige()

func prestige() -> void:
	prestige_system.prestige()

# ---------------------------------------------------------------- boosts

func boost_level(boost_id: StringName) -> int:
	return boost_system.boost_level(boost_id)

func boost_tier(boost_id: StringName) -> int:
	return boost_system.boost_tier(boost_id)

func boost_multiplier(boost_id: StringName) -> BigNumber:
	return boost_system.boost_multiplier(boost_id)

func boost_next_gain(boost_id: StringName) -> float:
	return boost_system.next_level_gain(boost_id)

func boost_cost(boost_id: StringName) -> BigNumber:
	return boost_system.boost_cost(boost_id)

func is_boost_maxed(boost_id: StringName) -> bool:
	return boost_system.is_maxed(boost_id)

func is_boost_unlocked(boost_id: StringName) -> bool:
	return boost_system.is_unlocked(boost_id)

func boost_max_level(boost_id: StringName) -> int:
	return boost_system.max_level(boost_id)

func can_buy_boost(boost_id: StringName) -> bool:
	return boost_system.can_buy_boost(boost_id)

func buy_boost(boost_id: StringName) -> bool:
	return boost_system.buy_boost(boost_id)

# ---------------------------------------------------------------- well

func is_well_pumping() -> bool:
	return water_system.is_pumping()

func water_pump_yield() -> BigNumber:
	return water_system.pump_yield()

func water_pump_interval() -> int:
	return water_system.interval()

func ticks_until_water_pump() -> int:
	return water_system.ticks_until_pump(player_data.tick_count)

func project_level(project_id: StringName) -> int:
	return well_system.level(project_id)

func project_max_level(project_id: StringName) -> int:
	return well_system.max_level(project_id)

func project_cost(project_id: StringName) -> BigNumber:
	return well_system.cost(project_id)

func is_project_unlocked(project_id: StringName) -> bool:
	return well_system.is_unlocked(project_id)

func project_min_levels(project_id: StringName) -> int:
	return well_system.min_project_levels(project_id)

func well_total_levels() -> int:
	return well_system.total_levels()

func is_project_maxed(project_id: StringName) -> bool:
	return well_system.is_maxed(project_id)

func can_invest_project(project_id: StringName) -> bool:
	return well_system.can_invest(project_id)

func invest_project(project_id: StringName) -> bool:
	return well_system.invest(project_id)

func is_project_boon_unlocked(project_id: StringName, index: int) -> bool:
	return well_system.is_boon_unlocked(project_id, index)

func project_boon_amount(project_id: StringName, index: int) -> BigNumber:
	return well_system.boon_amount(project_id, index, resolve_context)

func project_boon_next_level_delta(project_id: StringName, index: int) -> BigNumber:
	return well_system.boon_next_level_delta(project_id, index, resolve_context)

# ---------------------------------------------------------------- growth

func player_level() -> int:
	return player_level_system.level()

## {level, into, need, pct} - the bar and its caption in one read, so the two
## cannot be taken from different lifetime totals.
func player_level_progress() -> Dictionary:
	return player_level_system.level_progress()

func lp_invested(currency: CurrencyTypes.Types) -> int:
	return player_level_system.invested(currency)

func lp_invested_total() -> int:
	return player_level_system.invested_total()

func lp_available() -> int:
	return player_level_system.available_points()

func lp_global_double() -> BigNumber:
	return player_level_system.global_double()

func lp_points_to_next_double() -> int:
	return player_level_system.points_to_next_double()

func can_invest_lp(currency: CurrencyTypes.Types) -> bool:
	return player_level_system.can_invest(currency)

func invest_lp(currency: CurrencyTypes.Types) -> bool:
	return player_level_system.invest(currency)

# ---------------------------------------------------------------- daily reward

func can_claim_daily() -> bool:
	return daily_reward_system.can_claim()

func can_claim_daily_into(currency: CurrencyTypes.Types) -> bool:
	return daily_reward_system.can_claim_into(currency)

func daily_streak() -> int:
	return daily_reward_system.streak()

func daily_stacks(currency: CurrencyTypes.Types) -> int:
	return daily_reward_system.stacks(currency)

func claim_daily(currency: CurrencyTypes.Types) -> bool:
	return daily_reward_system.claim(currency)

# ---------------------------------------------------------------- fertilizer

func fertilizer_upgrade_defs() -> Array[FertilizerUpgradeDef]:
	return fertilizer_system.upgrades()

func fertilizer_level(id: StringName) -> int:
	return fertilizer_system.level(id)

func fertilizer_cost(id: StringName) -> BigNumber:
	return fertilizer_system.cost(id)

func can_buy_fertilizer(id: StringName) -> bool:
	return fertilizer_system.can_buy(id)

func buy_fertilizer(id: StringName) -> bool:
	return fertilizer_system.buy(id)

# ---------------------------------------------------------------- events

func events() -> Array[Dictionary]:
	return event_system.events()

func event_def(def_id: StringName) -> RandomEventDef:
	return event_system.def_for(def_id)

func event_amount(def: RandomEventDef) -> BigNumber:
	return event_system.amount_for(def)

func event_reward(event: Dictionary) -> BigNumber:
	return event_system.reward_for(event)

func can_fulfil_event(event: Dictionary) -> bool:
	return event_system.can_fulfil(event)

func collect_event(instance_id: int) -> bool:
	return event_system.collect(instance_id)

func fulfil_event(instance_id: int) -> bool:
	return event_system.fulfil(instance_id)

func skip_event(instance_id: int) -> bool:
	return event_system.skip(instance_id)

# ---------------------------------------------------------------- biomes

func is_screen_unlocked(screen_type: int) -> bool:
	return biome_system.is_screen_unlocked(screen_type)

func biome_def(key: StringName) -> BiomeDef:
	return biome_system.biome_def(key)

func biome_level(key: StringName) -> Dictionary:
	return biome_system.biome_level(key)

func biome_available_points(key: StringName) -> int:
	return biome_system.available_points(key)

func can_unlock_biome(key: StringName) -> bool:
	return biome_system.can_unlock(key)

func unlock_biome(key: StringName) -> bool:
	return biome_system.unlock(key)

func has_biome_auto_unlock(key: StringName) -> bool:
	return biome_system.has_auto_unlock(key)

func biome_auto_unlock_cost(key: StringName) -> BigNumber:
	return biome_system.auto_unlock_cost(key)

func can_buy_biome_auto_unlock(key: StringName) -> bool:
	return biome_system.can_buy_auto_unlock(key)

func buy_biome_auto_unlock(key: StringName) -> bool:
	return biome_system.buy_auto_unlock(key)

func is_biome_auto_unlock_enabled(key: StringName) -> bool:
	return biome_system.is_auto_unlock_enabled(key)

func toggle_biome_auto_unlock(key: StringName) -> void:
	biome_system.toggle_auto_unlock_enabled(key)

func biome_upgrade_ids(key: StringName) -> Array[StringName]:
	return biome_system.upgrade_ids(key)

func is_biome_upgrade_unlocked(id: StringName, key: StringName) -> bool:
	return biome_system.is_upgrade_unlocked(id, key)

func can_buy_biome_upgrade(id: StringName, key: StringName) -> bool:
	return biome_system.can_buy_upgrade(id, key)

## can_buy_biome_upgrade() without the point-budget half, for a caller testing
## many upgrades against one budget it read itself. See BiomeSystem.
func has_biome_upgrade_room(id: StringName, key: StringName) -> bool:
	return biome_system.has_upgrade_room(id, key)

func buy_biome_upgrade(id: StringName, key: StringName) -> bool:
	return biome_system.buy_upgrade(id, key)

# ---------------------------------------------------------------- biome size

func biome_size(key: StringName) -> int:
	return biome_system.size(key)

func biome_size_cost(key: StringName) -> BigNumber:
	return biome_system.size_cost(key)

func can_buy_biome_size(key: StringName) -> bool:
	return biome_system.can_buy_size(key)

## The signal stays here because views bind to App, not to BiomeSystem.
func buy_biome_size(key: StringName) -> bool:
	if not biome_system.buy_size(key):
		return false
	biome_size_changed.emit(key)
	return true

# ---------------------------------------------------------------- perks

func perk_def(id: StringName) -> PerkDef:
	return perk_system.perk_def(id)

func perk_status(id: StringName) -> String:
	return perk_system.status(id)

func can_buy_perk(id: StringName) -> bool:
	return perk_system.can_buy(id)

func buy_perk(id: StringName) -> bool:
	return perk_system.buy(id)

# ---------------------------------------------------------------- achievements

func achievement_tier(id: StringName) -> int:
	return achievement_system.tier(id)

func achievement_unclaimed(id: StringName) -> int:
	return achievement_system.unclaimed(id)

func has_achievement_claims() -> bool:
	return achievement_system.has_claims()

func achievement_goal(def: AchievementDef) -> BigNumber:
	return achievement_system.current_goal(def)

## What the next goal will pay once completed, for the archive's preview.
func achievement_reward(def: AchievementDef) -> BigNumber:
	return achievement_system.reward_for(def, achievement_system.tier(def.id))

## What collecting the tier already waiting pays. Zero when none is.
func achievement_claim_reward(def: AchievementDef) -> BigNumber:
	return achievement_system.claim_reward(def)

func claim_achievement(id: StringName) -> bool:
	return achievement_system.claim(id)

func claim_all_achievements() -> BigNumber:
	return achievement_system.claim_all()

func achievement_value(def: AchievementDef) -> BigNumber:
	return achievement_system.current_value(def)

func achievement_progress_ratio(def: AchievementDef) -> float:
	return achievement_system.progress_ratio(def)

func is_achievement_maxed(def: AchievementDef) -> bool:
	return achievement_system.is_maxed(def)

# ---------------------------------------------------------------- automation

func automation_level(id: StringName) -> int:
	return automation_system.level(id)

func automation_cost(id: StringName) -> BigNumber:
	return automation_system.cost(id)

func automation_runs_per_tick_at(id: StringName, lvl: int) -> float:
	return automation_system.runs_per_tick_at(id, lvl)

func automation_ticks_per_run_at(id: StringName, lvl: int) -> int:
	return automation_system.ticks_per_run_at(id, lvl)

func is_automation_owned(id: StringName) -> bool:
	return automation_system.is_owned(id)

func is_automation_active(id: StringName) -> bool:
	return automation_system.is_active(id)

func is_automation_maxed(id: StringName) -> bool:
	return automation_system.is_maxed(id)

func is_automation_unlocked(id: StringName) -> bool:
	return automation_system.is_unlocked(id)

func automation_max_level(id: StringName) -> int:
	return automation_system.max_level(id)

func can_buy_automation(id: StringName) -> bool:
	return automation_system.can_buy(id)

func buy_automation(id: StringName) -> bool:
	return automation_system.buy(id)

func set_automation_enabled(id: StringName, value: bool) -> void:
	automation_data.set_enabled(id, value)

# ---------------------------------------------------------------- ruins

func is_parasitic_control_active() -> bool:
	return mission_system.is_controlling()

func mission_slots() -> int:
	return mission_system.slots()

func mission_slots_used() -> int:
	return mission_system.slots_used()

func missions_completed() -> int:
	return ruins_data.missions_completed

func mission_def(mission_id: StringName) -> MissionDef:
	return mission_system.mission_def(mission_id)

func is_mission_unlocked(mission_id: StringName) -> bool:
	return mission_system.is_unlocked(mission_id)

func missions_until_mission_unlock(mission_id: StringName) -> int:
	return mission_system.missions_until_unlock(mission_id)

func mission_duration(mission_id: StringName, creature_id: StringName) -> float:
	return mission_system.duration_for(mission_id, creature_id)

func mission_payouts(mission_id: StringName, creature_id: StringName) -> Array[Dictionary]:
	return mission_system.payouts_for(mission_id, creature_id)

## The in-flight entry for this mission, or {} when none is out. One mission id
## can only be out once at a time: a creature is busy while it carries one, and
## the board sends one creature per errand.
func active_mission(mission_id: StringName) -> Dictionary:
	for entry in mission_system.active():
		if entry["mission_id"] == mission_id:
			return entry
	return {}

func mission_seconds_remaining(entry: Dictionary) -> float:
	return mission_system.seconds_remaining(entry)

func mission_progress_ratio(entry: Dictionary) -> float:
	return mission_system.progress_ratio(entry)

func is_mission_complete(entry: Dictionary) -> bool:
	return mission_system.is_complete(entry)

func collectable_mission_count() -> int:
	return mission_system.completed_count()

func can_send_mission(mission_id: StringName, creature_id: StringName) -> bool:
	return mission_system.can_send(mission_id, creature_id)

func send_mission(mission_id: StringName, creature_id: StringName) -> int:
	return mission_system.send(mission_id, creature_id)

func collect_mission(instance_id: int) -> bool:
	return mission_system.collect(instance_id)

func collect_all_missions() -> int:
	return mission_system.collect_all()

# ---------------------------------------------------------------- creatures

func creature_def(creature_id: StringName) -> CreatureDef:
	return creature_system.creature_def(creature_id)

func creature_rank(creature_id: StringName) -> int:
	return creature_system.rank(creature_id)

func creature_rank_cap(creature_id: StringName) -> int:
	return creature_system.rank_cap(creature_id)

func is_creature_recruited(creature_id: StringName) -> bool:
	return creature_system.is_recruited(creature_id)

func is_creature_unlocked(creature_id: StringName) -> bool:
	return creature_system.is_unlocked(creature_id)

func missions_until_creature_unlock(creature_id: StringName) -> int:
	return creature_system.missions_until_unlock(creature_id)

func is_creature_busy(creature_id: StringName) -> bool:
	return creature_system.is_busy(creature_id)

func is_creature_maxed(creature_id: StringName) -> bool:
	return creature_system.is_maxed(creature_id)

func creature_recruit_cost(creature_id: StringName) -> BigNumber:
	return creature_system.recruit_cost(creature_id)

func creature_rank_cost(creature_id: StringName) -> BigNumber:
	return creature_system.rank_cost(creature_id)

func can_recruit_creature(creature_id: StringName) -> bool:
	return creature_system.can_recruit(creature_id)

func recruit_creature(creature_id: StringName) -> bool:
	return creature_system.recruit(creature_id)

func can_rank_up_creature(creature_id: StringName) -> bool:
	return creature_system.can_rank_up(creature_id)

func rank_up_creature(creature_id: StringName) -> bool:
	return creature_system.rank_up(creature_id)

func creatures_available_for(mission: MissionDef) -> Array[CreatureDef]:
	return creature_system.available_for(mission)

func creature_has_affinity(creature_id: StringName, mission_id: StringName) -> bool:
	return creature_system.has_affinity(creature_id, mission_id)

# ---------------------------------------------------------------- ruins boosts

func mission_boost_level(boost_id: StringName) -> int:
	return mission_boost_system.level(boost_id)

func mission_boost_max_level(boost_id: StringName) -> int:
	return mission_boost_system.max_level(boost_id)

func mission_boost_cost(boost_id: StringName) -> BigNumber:
	return mission_boost_system.cost(boost_id)

func is_mission_boost_unlocked(boost_id: StringName) -> bool:
	return mission_boost_system.is_unlocked(boost_id)

func missions_until_boost_unlock(boost_id: StringName) -> int:
	return mission_boost_system.missions_until_unlock(boost_id)

func is_mission_boost_maxed(boost_id: StringName) -> bool:
	return mission_boost_system.is_maxed(boost_id)

func can_buy_mission_boost(boost_id: StringName) -> bool:
	return mission_boost_system.can_buy(boost_id)

func buy_mission_boost(boost_id: StringName) -> bool:
	return mission_boost_system.buy(boost_id)

func mission_boost_amount(boost_id: StringName) -> BigNumber:
	return mission_boost_system.amount(boost_id, resolve_context)

func mission_boost_next_level_delta(boost_id: StringName) -> BigNumber:
	return mission_boost_system.next_level_delta(boost_id, resolve_context)

