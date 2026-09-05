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
var currencies := load("res://data/currencies/all_currencies.tres") as Currencies

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
## Permanent upgrades granted by finishing an expedition, one UpgradeDef per
## expedition that carries rewards. Its own track rather than a corner of the
## boost ladder because nothing here is ever bought: MissionSystem grants a level
## when the expedition is collected, and the levels are a projection of
## RuinsData.completed_expeditions rather than save data of their own.
var expedition_upgrade_system: UpgradeSystem
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
var hero_system: HeroSystem
var worker_system: WorkerSystem
var mission_system: MissionSystem
var mission_boost_system: MissionBoostSystem

var biomes := load("res://data/biomes/all_biomes.tres") as BiomeList
var biomes_data: BiomesData
var biome_vms: Dictionary = {}  # StringName -> BiomeViewModel

var perk_branches := load("res://data/prestige/all_branches.tres") as PerkBranchList
var prestige_curve := load("res://data/prestige/res_prestige_curve.tres") as PrestigeCurveDef
var perk_defs: Dictionary = {}  # StringName -> PerkDef
var perk_vms: Dictionary = {}  # StringName -> PerkViewModel
var prestige_vm: PrestigeViewModel

var stats_data: StatsData
var stats_system: StatsSystem
var statistics_vm: StatisticsViewModel

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

var hero_defs := load("res://data/ruins/all_heroes.tres") as HeroList
var worker_cost := load("res://data/ruins/res_worker_cost.tres") as WorkerCostDef
var mission_defs := load("res://data/ruins/all_missions.tres") as MissionList
var mission_boosts := load("res://data/ruins/all_mission_boosts.tres") as MissionBoostList
var ruins_data: RuinsData
var hero_vms: Dictionary = {}       # StringName -> HeroViewModel
var mission_vms: Dictionary = {}        # StringName -> MissionViewModel
## StringName hero id -> HeroExpeditionViewModel, one per authored hero: the
## expedition board is one row per hero now, not one per place.
var hero_expedition_vms: Dictionary = {}
## StringName mission id -> FarmViewModel, one per authored farm.
var farm_vms: Dictionary = {}
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

## Set by SaveManager for the duration of the offline catch-up. Nothing the
## catch-up does is structural - it buys nothing, unlocks nothing - so the
## achievement ladder and the statistics overlay's structural sample have nothing
## new to read on any of the frames the loop yields across, and re-walking every
## achievement def ~50 times a second for the length of a catch-up is the single
## largest per-frame cost in it. SaveManager marks the flag dirty once when the
## loop ends, which banks every tier the gap crossed in one evaluate.
var offline_catchup := false

## Names the phase the main thread is in, for the watchdog thread to report if
## the main thread stops coming back. See FreezeWatchdog.
var watchdog: FreezeWatchdog

## Set by anything an achievement could measure, drained once per frame in
## _process. Evaluating per change would re-walk every achievement several times
## a tick, and the offline catch-up loop drives handle_tick() thousands of times
## in a row, so the flag collapses all of that into one evaluate per frame.
var _achievements_dirty := true

const BASE_TICK_DURATION := 10.0
const MIN_TICK_DURATION := 1.0  # floor so a stacked tick_rate discount can't reach zero

func _ready() -> void:
	# First, so a lock anywhere in the rest of the boot is reported too.
	watchdog = FreezeWatchdog.new()
	add_child(watchdog)

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
	# Seeded before BoostSystem is built: LEVELS_PER_TIER decides where the tier
	# boundaries fall, and the first tier def is registered off the back of it.
	# The rest are grown by BoostSystem as the ladder climbs - there is no last
	# tier to register up front.
	BoostTiers.configure(boosts)

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

	expedition_upgrade_system = UpgradeSystem.new()
	for def in ExpeditionRewardTree.build(mission_defs):
		expedition_upgrade_system.register(def)

	production_system = ProductionSystem.new(upgrade_system, biome_upgrade_system,
		prestige_upgrade_system, resolve_context, boost_upgrade_system,
		project_upgrade_system, growth_upgrade_system, fertilizer_upgrade_system,
		mission_upgrade_system, nodes.mycelium_nodes, expedition_upgrade_system)
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
		production_system, upgrade_system, biome_upgrade_system, biome_system, prestige_curve)

	for node in nodes.mycelium_nodes:
		var mycelium_data := MyceliumNodeData.new(player_data, node, prestige_upgrade_system)
		mycelium_node_data.append(mycelium_data)
		mycelium_node_vms.append(MyceliumNodeViewModel.new(player_data, mycelium_data))
		_track_manual_count(node)

	achievement_progress = AchievementProgress.new()
	achievement_system = AchievementSystem.new(achievements, achievement_progress, player_data,
		upgrade_system, biomes_data)

	boost_system = BoostSystem.new(player_data, boost_upgrade_system, boosts,
		prestige_upgrade_system, production_system)

	well_system = WellSystem.new(player_data, project_upgrade_system, projects,
		prestige_upgrade_system)

	daily_reward_data = DailyRewardData.new()
	player_level_system = PlayerLevelSystem.new(player_data, growth_upgrade_system,
		growth_producers, production_system)
	daily_reward_system = DailyRewardSystem.new(daily_reward_data, growth_upgrade_system,
		growth_producers)

	# Last of the systems, because it watches all of them: it needs the level
	# ladder and the daily streak for its counts, and the tick system for the
	# payout a peak is measured from.
	stats_data = StatsData.new()
	stats_system = StatsSystem.new(stats_data, player_data, biomes, biomes_data,
		nodes.mycelium_nodes, tick_system, upgrade_system, prestige_upgrade_system,
		player_level_system, daily_reward_data)
	_connect_stats_sources()

	# Built after biomes_data, which gates the crystal event, and before the VMs
	# that read them back through App.
	fertilizer_system = FertilizerSystem.new(player_data, fertilizer_upgrade_system,
		fertilizer_upgrades)
	events_data = EventsData.new()
	# The two registries at the end are what lets it work out which biome owns the
	# screen a currency is shown on, so an event never offers a resource the
	# player has no home for yet.
	event_system = EventSystem.new(events_data, player_data, biomes_data,
		fertilizer_system, random_events, screens, biomes)

	# The Ruins, in dependency order: the roster before the board that sends it
	# out, and the board before nothing - the boost ladder only reads the tally.
	# All three share one RuinsData, which is what lets HeroSystem answer
	# "is this hero out right now" without knowing about missions.
	ruins_data = RuinsData.new()
	hero_system = HeroSystem.new(ruins_data, player_data, hero_defs,
		production_system)
	worker_system = WorkerSystem.new(ruins_data, player_data, worker_cost, production_system)
	mission_system = MissionSystem.new(ruins_data, player_data, biomes_data,
		production_system, hero_system, mission_defs, prestige_upgrade_system,
		expedition_upgrade_system, worker_system)
	# The reward track is a projection of which expeditions are finished, so a
	# fresh game seeds it here and a loaded one re-seeds it in load_from_save().
	mission_system.sync_expedition_rewards()
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
	statistics_vm = StatisticsViewModel.new()
	for def in automations.automations:
		automation_vms[def.id] = AutomationViewModel.new(def)
	for def in biomes.biomes:
		biome_sequence_vms[def.key] = BiomeSequenceViewModel.new(def.key, def)
	for def in boosts.boosts:
		boost_vms[def.id] = BoostViewModel.new(def.id, def)
	for def in projects.projects:
		project_vms[def.id] = ProjectViewModel.new(def.id, def)
	for def in hero_defs.heroes:
		hero_vms[def.id] = HeroViewModel.new(def.id, def)
		hero_expedition_vms[def.id] = HeroExpeditionViewModel.new(def.id, def)
	for def in mission_defs.missions:
		mission_vms[def.id] = MissionViewModel.new(def.id, def)
		if def.is_farm:
			farm_vms[def.id] = FarmViewModel.new(def.id, def)
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

## Two jobs, both of them at most one pass a frame and both only when something
## actually moved: paying off what an automation's tick budget cut short, and
## re-walking the achievement ladder. See AutomationSystem.handle_frame() and
## _achievements_dirty.
##
## Both consumers ride the one flag rather than each keeping its own: the
## achievement ladder and the statistics overlay's structural peaks read the same
## handful of sources - node counts, upgrade levels, biome unlocks, prestiges - so
## a second flag would be the first one under another name.
func _process(_delta: float) -> void:
	# Everything outside the two blocks below is the engine's own frame - input,
	# layout, drawing - so "frame" is the phase a lock in a view reports under.
	watchdog.mark("frame")
	# Ahead of the achievement half, so a purchase made on this frame is counted
	# on this frame. Gated on the same flag as the tick's automation block:
	# SaveManager clears it for the whole offline catch-up, and that loop yields
	# across frames, so without the gate the drain would run inside it.
	if automations_running and automation_system.has_owed():
		# Batched for the same reason handle_tick() batches: one automation may
		# buy many levels in this one call, and every upgrades_changed listener
		# refreshes synchronously. The player sees one frame, so they get one
		# refresh.
		watchdog.mark("frame: automation drain")
		upgrade_system.begin_batch()
		biome_upgrade_system.begin_batch()
		prestige_upgrade_system.begin_batch()
		automation_system.handle_frame()
		prestige_upgrade_system.end_batch()
		biome_upgrade_system.end_batch()
		upgrade_system.end_batch()
	if not _achievements_dirty:
		return
	_achievements_dirty = false
	watchdog.mark("frame: achievement evaluate")
	achievement_system.evaluate()
	watchdog.mark("frame: stats sample")
	stats_system.sample_counts()

func mark_achievements_dirty() -> void:
	_achievements_dirty = true

## The moments StatsSystem cannot reconstruct afterwards. Each of these is gone
## by the time anything could go looking for it: a currency spike is spent, a
## biome unlock is undone by the next prestige, and the run a sporation ends is
## wiped by the sporation itself.
##
## The peaks that a purchase moves are not here - they ride the once-a-frame
## dirty flag in _process() instead, since a count nothing bought cannot have
## changed.
func _connect_stats_sources() -> void:
	for field in StatsSystem.CURRENCY_FIELDS:
		player_data.connect("%s_changed" % field, stats_system.note_currency.bind(StringName(field)))
	biomes_data.biome_unlocked.connect(stats_system.note_biome_unlocked)
	prestige_system.prestiging.connect(stats_system.note_prestige)
	for mycelium_data in mycelium_node_data:
		mycelium_data.node_bought.connect(stats_system.note_node_bought)

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
		# Hand-bought nodes are the Meadow's XP, so a purchase can level it. The
		# next tick would pick it up anyway; doing it here is what makes the perk
		# card's "now +x%" move as the player buys rather than a tick later.
		biome_system.sync_levels()
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
		"stats": stats_data.to_save(),
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
	# Ahead of player_data, whose setters fire the currency signals StatsSystem
	# raises peaks from. Loaded second, this would clear those peaks again - and
	# on a save written before stats existed it would clear them for nothing,
	# leaving every "most held" record empty until the balance next moved.
	stats_data.load_from_save(game.get("stats", {}))
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
	# Before the levels, not after: from_save() drops any id it has no def for, and
	# a save written past tier one has ids this boot has not grown to yet.
	var saved_boosts: Dictionary = game.get("boost_upgrades", {})
	boost_system.ensure_tiers_for_save(saved_boosts)
	boost_upgrade_system.from_save(saved_boosts)
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
	# The expedition reward track is a projection of the expeditions just loaded,
	# not a saved field, for the same reason - so it is rebuilt here too.
	mission_system.sync_expedition_rewards()
	# Only a device clock moved backwards can leave a mission's start in the
	# future, and only a load can be the first thing to notice.
	mission_system.sync_clock_rollback()
	# Every whole cycle the farms turned while the game was closed, paid in one
	# O(1) sweep. This is the entire offline catch-up for the Ruins: the missions
	# themselves need none, since completion is derived from two timestamps.
	watchdog.mark("tick: farms")
	mission_system.settle_farms()
	daily_reward_data.load_from_save(game.get("daily_reward", {}))
	# Only a device clock moved backwards can leave a last-claim day in the
	# future, and only a load can be the first thing to notice.
	daily_reward_system.sync_clock_rollback()
	# Last, once every XP source a biome level reads has been loaded: the nodes,
	# the symbiosis levels, the achievement tiers, the well projects and the
	# missions are all in by here. Without it the first tick of a loaded session
	# resolves every level-scaled perk against level 1.
	biome_system.sync_levels()

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

## The other two per-tick invariants a long run of ticks hoists, alongside
## node_production_bonuses(). See TickSystem.manual_node_counts() and
## WaterPumpPlan for why they are safe to reuse.
func manual_node_counts() -> Array[BigNumber]:
	return tick_system.manual_node_counts()

func water_pump_plan() -> WaterPumpPlan:
	return water_system.pump_plan()

## What every node produces in one tick, summed. The same figure the balance
## chart's `production` track plots and the statistics overlay reports as the
## run's production per tick, so the two cannot drift apart.
func total_production() -> BigNumber:
	var production := BigNumber.new(0.0, 0)
	var bonuses: Array[BigNumber] = node_production_bonuses()
	for i in nodes.mycelium_nodes.size():
		var node: MyceliumNode = nodes.mycelium_nodes[i]
		var count := node.auto_nodes.add(BigNumber.from_value(node.manual_nodes))
		production = production.add(count.mul(bonuses[i]))
	return production

## Pass the hoisted invariants - bonuses, pump plan, manual counts - to drive a
## long run of ticks without recomputing them; leave them empty for the live
## timer, which pays for one tick at a time anyway.
func handle_tick(bonuses: Array[BigNumber] = [], pump: WaterPumpPlan = null,
		manual: Array[BigNumber] = []) -> void:
	# Before production, so a level earned last tick pays into this one. Cheap
	# and usually a no-op: it only invalidates when a biome actually levelled.
	watchdog.mark("tick: sync_levels")
	biome_system.sync_levels()
	watchdog.mark("tick: production")
	tick_system.handle_tick(bonuses, pump, manual)
	# Straight after the cascade, so the peak it records is this tick's payout
	# rather than one an automation below has already spent into.
	watchdog.mark("tick: stats")
	stats_system.handle_tick()
	# Live ticks only, same as the two gates below: a catch-up moves nothing the
	# achievement ladder or the structural stats sample read, so the flag would
	# only buy a full re-walk on every frame the loop yields across. SaveManager
	# marks it once at the end instead.
	if not offline_catchup:
		_achievements_dirty = true
	# Live ticks only. A progress quest measures time the player was here for, so
	# the offline catch-up must not walk one to its goal - same reason the spawn
	# timer checks this flag.
	if events_running:
		watchdog.mark("tick: events")
		event_system.handle_tick()
	# The farms. Not gated on a running flag and not skipped for a catch-up: a
	# farm pays on the wall clock whether or not the game was open, and the sweep
	# only decides when the payout lands. It is idempotent by construction - a
	# second call in the same second finds no whole cycle - so a catch-up running
	# it once a tick pays exactly what one call at the end would have.
	mission_system.settle_farms()
	# After production, so an automation spends the nutrients this tick just
	# paid out rather than always working a tick behind.
	if automations_running:
		watchdog.mark("tick: automations")
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
##
## Priced at the tier being filled - claimed plus banked - rather than at the
## claimed count, which is the tier of whatever is still waiting to be collected.
func achievement_reward(def: AchievementDef) -> BigNumber:
	return achievement_system.reward_for(def,
		achievement_system.tier(def.id) + achievement_system.unclaimed(def.id))

## What collecting the tier already waiting pays. Zero when none is.
func achievement_claim_reward(def: AchievementDef) -> BigNumber:
	return achievement_system.claim_reward(def)

func claim_achievement(id: StringName) -> bool:
	watchdog.mark("claim achievement %s" % id)
	return achievement_system.claim(id)

func claim_all_achievements() -> BigNumber:
	watchdog.mark("claim all achievements")
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

func expeditions_out() -> int:
	return mission_system.expeditions_out()

func farm_slots() -> int:
	return mission_system.farm_slots()

func farm_slots_used() -> int:
	return mission_system.farm_slots_used()

func missions_completed() -> int:
	return ruins_data.missions_completed

func mission_def(mission_id: StringName) -> MissionDef:
	return mission_system.mission_def(mission_id)

func is_mission_unlocked(mission_id: StringName) -> bool:
	return mission_system.is_unlocked(mission_id)

func is_mission_completed(mission_id: StringName) -> bool:
	return mission_system.is_completed(mission_id)

func mission_chain(hero_id: StringName) -> Array[MissionDef]:
	return mission_system.chain(hero_id)

func chain_length(hero_id: StringName) -> int:
	return mission_system.chain_length(hero_id)

func chain_position(hero_id: StringName) -> int:
	return mission_system.chain_position(hero_id)

func next_chain_step(hero_id: StringName) -> MissionDef:
	return mission_system.next_step(hero_id)

func sendable_step(hero_id: StringName) -> StringName:
	return mission_system.sendable_step(hero_id)

func levels_until_mission_unlock(mission_id: StringName) -> int:
	return mission_system.levels_until_unlock(mission_id)

func missions_until_mission_unlock(mission_id: StringName) -> int:
	return mission_system.missions_until_unlock(mission_id)

func mission_duration(mission_id: StringName, hero_id: StringName,
		workers: int = 0) -> float:
	return mission_system.duration_for(mission_id, hero_id, workers)

func mission_payouts(mission_id: StringName, hero_id: StringName) -> Array[Dictionary]:
	return mission_system.payouts_for(mission_id, hero_id)

## The in-flight entry for this mission, or {} when none is out. One mission id
## can only be out once at a time: a hero is busy while it carries one, and
## the board sends one hero per errand.
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

func active_expeditions() -> Array[Dictionary]:
	return mission_system.active_expeditions()

func active_farms() -> Array[Dictionary]:
	return mission_system.active_farms()

func farm_progress_ratio(entry: Dictionary) -> float:
	return mission_system.farm_progress_ratio(entry)

func can_start_farm(mission_id: StringName, workers: int = 1) -> bool:
	return mission_system.can_start_farm(mission_id, workers)

func start_farm(mission_id: StringName, workers: int = 1) -> int:
	return mission_system.start_farm(mission_id, workers)

func set_farm_workers(instance_id: int, workers: int) -> bool:
	return mission_system.set_farm_workers(instance_id, workers)

func stop_farm(instance_id: int) -> bool:
	return mission_system.stop_farm(instance_id)

func can_send_mission(mission_id: StringName, hero_id: StringName) -> bool:
	return mission_system.can_send(mission_id, hero_id)

func send_mission(mission_id: StringName, hero_id: StringName) -> int:
	return mission_system.send(mission_id, hero_id)

func collect_mission(instance_id: int) -> bool:
	return mission_system.collect(instance_id)

func collect_all_missions() -> int:
	return mission_system.collect_all()

# ---------------------------------------------------------------- workers

func workers_owned() -> int:
	return worker_system.owned()

func workers_idle() -> int:
	return worker_system.idle()

func worker_prices() -> Array[Dictionary]:
	return worker_system.prices()

func can_hire_worker() -> bool:
	return worker_system.can_hire()

func hire_worker() -> bool:
	return worker_system.hire()

func max_workers_per_farm(mission_id: StringName) -> int:
	return worker_system.max_per_farm(mission_id)

func most_workers_available_for(mission_id: StringName, already_here: int) -> int:
	return worker_system.most_available_for(mission_id, already_here)

# ---------------------------------------------------------------- heroes

func hero_def(hero_id: StringName) -> HeroDef:
	return hero_system.hero_def(hero_id)

func hero_level(hero_id: StringName) -> int:
	return hero_system.level(hero_id)

func hero_level_cap(hero_id: StringName) -> int:
	return hero_system.level_cap(hero_id)

func is_hero_recruited(hero_id: StringName) -> bool:
	return hero_system.is_recruited(hero_id)

func is_hero_unlocked(hero_id: StringName) -> bool:
	return hero_system.is_unlocked(hero_id)

func missions_until_hero_unlock(hero_id: StringName) -> int:
	return hero_system.missions_until_unlock(hero_id)

func is_hero_busy(hero_id: StringName) -> bool:
	return hero_system.is_busy(hero_id)

func is_hero_maxed(hero_id: StringName) -> bool:
	return hero_system.is_maxed(hero_id)

func hero_recruit_cost(hero_id: StringName) -> BigNumber:
	return hero_system.recruit_cost(hero_id)

func hero_recruit_prices(hero_id: StringName) -> Array[Dictionary]:
	return hero_system.recruit_prices(hero_id)

func hero_level_cost(hero_id: StringName) -> BigNumber:
	return hero_system.level_cost(hero_id)

func can_recruit_hero(hero_id: StringName) -> bool:
	return hero_system.can_recruit(hero_id)

func recruit_hero(hero_id: StringName) -> bool:
	return hero_system.recruit(hero_id)

func can_level_up_hero(hero_id: StringName) -> bool:
	return hero_system.can_level_up(hero_id)

func level_up_hero(hero_id: StringName) -> bool:
	return hero_system.level_up(hero_id)

func is_hero_available(hero_id: StringName) -> bool:
	return hero_system.is_available(hero_id)

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

