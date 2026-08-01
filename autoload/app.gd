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
var resolve_context := ResolveContext.new()

## Game rules, split out by domain. Each is constructed with the state it needs
## and holds no reference back to App, so it can be built and exercised without
## the autoload existing. App keeps a delegating method per public entry point
## (bottom of this file) so ViewModels can keep binding to App.*.
var production_system: ProductionSystem
var biome_system: BiomeSystem
var perk_system: PerkSystem

var biomes := load("res://data/biomes/all_biomes.tres") as BiomeList
var biomes_data: BiomesData
var biome_vms: Dictionary = {}  # StringName -> BiomeViewModel

var perk_branches := load("res://data/prestige/all_branches.tres") as PerkBranchList
var perk_defs: Dictionary = {}  # StringName -> PerkDef
var perk_vms: Dictionary = {}  # StringName -> PerkViewModel
var prestige_vm: PrestigeViewModel

const SYMBIOSIS_UPGRADES_PATH := "res://data/upgrades/symbiosis/"
const PRESTIGE_UPGRADES_PATH := "res://data/upgrades/prestige/"
const BIOME_UPGRADES_PATH := "res://data/upgrades/biomes/"

const BASE_TICK_DURATION := 10.0
const MIN_TICK_DURATION := 1.0  # floor so a stacked tick_rate discount can't reach zero

func _ready() -> void:
	player_data = PlayerData.new()
	player_vm = PlayerViewModel.new(player_data)

	upgrade_system = UpgradeSystem.new()
	for def in _load_upgrade_defs(SYMBIOSIS_UPGRADES_PATH):
		upgrade_system.register(def)

	prestige_upgrade_system = UpgradeSystem.new()
	for def in _load_upgrade_defs(PRESTIGE_UPGRADES_PATH):
		prestige_upgrade_system.register(def)

	biome_upgrade_system = UpgradeSystem.new()
	for def in _load_upgrade_defs(BIOME_UPGRADES_PATH):
		biome_upgrade_system.register(def)

	production_system = ProductionSystem.new(upgrade_system, biome_upgrade_system,
		prestige_upgrade_system, resolve_context)

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
	biome_system.unlock_starting_biomes()
	for def in biomes.biomes:
		biome_vms[def.key] = BiomeViewModel.new(def.key, def)

	for node in nodes.mycelium_nodes:
		var mycelium_data := MyceliumNodeData.new(player_data, node, prestige_upgrade_system)
		mycelium_node_data.append(mycelium_data)
		mycelium_node_vms.append(MyceliumNodeViewModel.new(player_data, mycelium_data))
		_track_manual_count(node)

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
	_update_tick_duration()

## Recursively loads every UpgradeDef .tres under path. Other resource types in
## the tree (UpgradeEffectDef, ScalingSourceDef) are skipped.
func _load_upgrade_defs(path: String) -> Array[UpgradeDef]:
	var defs: Array[UpgradeDef] = []
	var dir := DirAccess.open(path)
	if dir == null:
		push_error("Could not open %s (%s)" % [path, DirAccess.get_open_error()])
		return defs
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		var full_path := path.path_join(file_name)
		if dir.current_is_dir():
			defs.append_array(_load_upgrade_defs(full_path))
		elif file_name.ends_with(".tres") or file_name.ends_with(".tres.remap"):
			# Packed builds list resources as "<name>.tres.remap". The real
			# resource lives at the path with ".remap" stripped.
			var res := load(full_path.trim_suffix(".remap"))
			if res is UpgradeDef:
				defs.append(res)
		file_name = dir.get_next()
	dir.list_dir_end()
	return defs

func _track_manual_count(node: MyceliumNode) -> void:
	var key := StringName("ManualNode%d" % node.node_id)
	resolve_context.manual_counts[key] = node.manual_nodes
	node.manual_nodes_changed.connect(func(value: int) -> void:
		resolve_context.manual_counts[key] = value
		upgrade_system.invalidate()
	)

## Per-node production multiplier, indexed like nodes.mycelium_nodes. Callers
## driving many ticks back-to-back (offline catch-up) compute this once and pass
## it into handle_tick(): node_production_bonus() is a chain of ~9
## UpgradeSystem.modify() calls, and redoing it per node per tick dominates a
## long catch-up loop. Safe to hoist because its only live inputs are upgrade
## levels and manual node counts, and every ScalingSourceDef kind is
## player-action driven (see ResolveContext), so nothing goes stale mid-loop.
func node_production_bonuses() -> Array[BigNumber]:
	var bonuses: Array[BigNumber] = []
	for i in range(nodes.mycelium_nodes.size()):
		var node := mycelium_node_data[i].node
		bonuses.append(node_production_bonus(StringName(str(node.node_id))))
	return bonuses

func handle_tick(bonuses: Array[BigNumber] = []) -> void:
	player_data.tick_count += 1
	if bonuses.is_empty():
		bonuses = node_production_bonuses()
	for i in range(nodes.mycelium_nodes.size() -1, -1, -1):
		var node := mycelium_node_data[i].node
		var node_change := node.auto_nodes.add(BigNumber.from_value(node.manual_nodes))
		node_change = node_change.mul(bonuses[i])
		if i != 0:
			var receiving_node := mycelium_node_data[i - 1].node
			receiving_node.auto_nodes = receiving_node.auto_nodes.add(node_change)
		else:
			player_data.nutrients = player_data.nutrients.add(node_change)

func can_prestige() -> bool:
	if not biomes_data.is_unlocked(&"permafrost"):
		return false
	return preview_biomass_gain().gt(BigNumber.new(0.0, 0))

## Resets the current run (nutrients, water, tick_count, node purchases,
## symbiosis upgrades, biome unlocks) and converts it into biomass. Perks in
## prestige_upgrade_system are untouched, they persist across prestiges.
func prestige() -> void:
	player_data.biomass = player_data.biomass.add(preview_biomass_gain())
	player_data.nutrients = BigNumber.from_value(1.0)
	player_data.water = BigNumber.from_value(0.0)
	player_data.tick_count = 0
	player_data.prestige_count += 1

	for node in nodes.mycelium_nodes:
		node.manual_nodes = 0 if node.node_id != 0 else 1
		node.auto_nodes = BigNumber.new(0.0, 0)

	upgrade_system.reset()
	biome_upgrade_system.reset()
	biome_system.reset()

func _update_tick_duration() -> void:
	tick_timer.wait_time = tick_duration()

# ---------------------------------------------------------------------------
# Delegators. The rules live in ProductionSystem / BiomeSystem / PerkSystem,
# which hold no App reference and can be built standalone. These thin forwards
# keep App the single entry point the ViewModels bind to.
# ---------------------------------------------------------------------------

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

func preview_biomass_gain() -> BigNumber:
	var base := PrestigeCalculator.calculate_biomass_gain(player_data.tick_count, player_data.nutrients)
	return production_system.modify_biomass_gain(base)

func tick_duration() -> float:
	return production_system.tick_duration(BASE_TICK_DURATION, MIN_TICK_DURATION)

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

func biome_upgrade_ids(key: StringName) -> Array[StringName]:
	return biome_system.upgrade_ids(key)

func is_biome_upgrade_unlocked(id: StringName, key: StringName) -> bool:
	return biome_system.is_upgrade_unlocked(id, key)

func can_buy_biome_upgrade(id: StringName, key: StringName) -> bool:
	return biome_system.can_buy_upgrade(id, key)

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
