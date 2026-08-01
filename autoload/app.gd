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
var tick_system: TickSystem
var prestige_system: PrestigeSystem

var biomes := load("res://data/biomes/all_biomes.tres") as BiomeList
var biomes_data: BiomesData
var biome_vms: Dictionary = {}  # StringName -> BiomeViewModel

var perk_branches := load("res://data/prestige/all_branches.tres") as PerkBranchList
var perk_defs: Dictionary = {}  # StringName -> PerkDef
var perk_vms: Dictionary = {}  # StringName -> PerkViewModel
var prestige_vm: PrestigeViewModel

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

	production_system = ProductionSystem.new(upgrade_system, biome_upgrade_system,
		prestige_upgrade_system, resolve_context)
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
	biome_system.unlock_starting_biomes()
	for def in biomes.biomes:
		biome_vms[def.key] = BiomeViewModel.new(def.key, def)

	prestige_system = PrestigeSystem.new(player_data, biomes_data, nodes.mycelium_nodes,
		production_system, upgrade_system, biome_upgrade_system, biome_system)

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
