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
var screens := load("res://data/screens/all_screens.tres") as Screens

var offline_income_vm: OfflineIncomeViewModel
var tick_timer: Timer

var upgrade_system: UpgradeSystem
var prestige_upgrade_system: UpgradeSystem
var biome_upgrade_system: UpgradeSystem
## Levels of the two geode boosts, one UpgradeDef per boost per tier. A track of
## its own rather than a corner of the prestige one: geodes are permanent, the
## defs are generated from GeodeTiers instead of authored, and it saves and
## resets on its own terms.
var geode_upgrade_system: UpgradeSystem
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

var geode_boosts := load("res://data/geodes/all_geode_boosts.tres") as GeodeBoostList
var geode_system: GeodeSystem
var geode_boost_vms: Dictionary = {}  # StringName -> GeodeBoostViewModel
var geodes_vm: GeodesViewModel

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

	geode_upgrade_system = UpgradeSystem.new()
	for def in GeodeBoostTree.build(geode_boosts):
		geode_upgrade_system.register(def)

	production_system = ProductionSystem.new(upgrade_system, biome_upgrade_system,
		prestige_upgrade_system, resolve_context, geode_upgrade_system)
	tick_system = TickSystem.new(nodes.mycelium_nodes, player_data, production_system)

	for perk in PerkTree.build(perk_branches):
		prestige_upgrade_system.register(perk)
		perk_defs[perk.id] = perk
	perk_system = PerkSystem.new(perk_defs, prestige_upgrade_system, player_data)
	# Built after perk_system: PerkViewModel reads perk state through App, which
	# forwards to it, so it must exist before the first VM is constructed.
	for id in perk_defs:
		perk_vms[id] = PerkViewModel.new(id, perk_defs[id])
	prestige_vm = PrestigeViewModel.new()

	biomes_data = BiomesData.new()
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

	geode_system = GeodeSystem.new(player_data, geode_upgrade_system, production_system,
		geode_boosts, prestige_upgrade_system)

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
	crystal_caves_vm = CrystalCavesViewModel.new()
	for def in geode_boosts.boosts:
		geode_boost_vms[def.id] = GeodeBoostViewModel.new(def.id, def)
	geodes_vm = GeodesViewModel.new()

	screens_data = ScreensData.new(screens.screens, screens.initial_screen)
	screens_vm = ScreensViewModel.new(screens_data)

	offline_income_vm = OfflineIncomeViewModel.new()

	tick_timer = Timer.new()
	tick_timer.wait_time = BASE_TICK_DURATION
	tick_timer.autostart = true
	tick_timer.timeout.connect(func() -> void:
		handle_tick()
	)
	add_child(tick_timer)

	upgrade_system.upgrades_changed.connect(_update_tick_duration)
	biome_upgrade_system.upgrades_changed.connect(_update_tick_duration)
	prestige_upgrade_system.upgrades_changed.connect(_update_tick_duration)
	geode_upgrade_system.upgrades_changed.connect(_update_tick_duration)
	_update_tick_duration()

	_connect_achievement_sources()

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
	geode_upgrade_system.upgrades_changed.connect(mark_achievements_dirty)
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

func _update_tick_duration() -> void:
	tick_timer.wait_time = tick_duration()

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
	# After production, so an automation spends the nutrients this tick just
	# paid out rather than always working a tick behind.
	if automations_running:
		# Batched: one automation may buy up to MAX_RUNS_PER_TICK levels in this
		# one call, and every upgrades_changed listener (tick duration, the biome
		# panels' slot grids, every node card) refreshes synchronously. The
		# player sees one tick, so they get one refresh.
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

# ---------------------------------------------------------------- prestige

func preview_biomass_gain() -> BigNumber:
	return prestige_system.preview_biomass_gain()

func can_prestige() -> bool:
	return prestige_system.can_prestige()

func prestige() -> void:
	prestige_system.prestige()

# ---------------------------------------------------------------- geodes

func geode_conversion_rate() -> BigNumber:
	return geode_system.conversion_rate()

func available_geodes() -> BigNumber:
	return geode_system.available_geodes()

func geode_boost_crystal_cost(boost_id: StringName) -> BigNumber:
	return geode_system.boost_crystal_cost(boost_id)

func geode_boost_level(boost_id: StringName) -> int:
	return geode_system.boost_level(boost_id)

func geode_boost_tier(boost_id: StringName) -> int:
	return geode_system.boost_tier(boost_id)

func geode_boost_multiplier(boost_id: StringName) -> BigNumber:
	return geode_system.boost_multiplier(boost_id)

func geode_boost_next_gain(boost_id: StringName) -> float:
	return geode_system.next_level_gain(boost_id)

func geode_boost_cost(boost_id: StringName) -> BigNumber:
	return geode_system.boost_cost(boost_id)

func is_geode_boost_maxed(boost_id: StringName) -> bool:
	return geode_system.is_maxed(boost_id)

func is_geode_boost_unlocked(boost_id: StringName) -> bool:
	return geode_system.is_unlocked(boost_id)

func geode_boost_max_level(boost_id: StringName) -> int:
	return geode_system.max_level(boost_id)

func can_buy_geode_boost(boost_id: StringName) -> bool:
	return geode_system.can_buy_boost(boost_id)

func buy_geode_boost(boost_id: StringName) -> bool:
	return geode_system.buy_boost(boost_id)

# ---------------------------------------------------------------- biomes

func is_screen_unlocked(screen_type: int) -> bool:
	return biome_system.is_screen_unlocked(screen_type)

func biome_def(key: StringName) -> BiomeDef:
	return biome_system.biome_def(key)

func biome_def_for_screen(screen_type: int) -> BiomeDef:
	return biome_system.biome_def_for_screen(screen_type)

func biome_xp(key: StringName) -> int:
	return biome_system.biome_xp(key)

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

func automation_runs_per_tick(id: StringName) -> float:
	return automation_system.runs_per_tick(id)

func automation_ticks_per_run(id: StringName) -> int:
	return automation_system.ticks_per_run(id)

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
