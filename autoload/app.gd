extends Node
## AUTOLOAD "App" — the composition root.
## Owns the Models and ViewModels for the app's lifetime.
## Register in Project Settings > Autoload as "App".
##
## Models and VMs are RefCounted, so this autoload holding references
## is what keeps them alive. Views come and go with the scene tree.

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

var biomes := load("res://data/biomes/all_biomes.tres") as BiomeList
var biomes_data: BiomesData
var biome_vms: Dictionary = {}  # StringName -> BiomeViewModel

var perk_branches := load("res://data/prestige/all_branches.tres") as PerkBranchList
var perk_defs: Dictionary = {}  # StringName -> PerkDef

const SYMBIOSIS_UPGRADES_PATH := "res://data/upgrades/symbiosis/"
const PRESTIGE_UPGRADES_PATH := "res://data/upgrades/prestige/"
const BIOME_UPGRADES_PATH := "res://data/upgrades/biomes/"

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

	for perk in PerkTree.build(perk_branches):
		prestige_upgrade_system.register(perk)
		perk_defs[perk.id] = perk

	biomes_data = BiomesData.new()
	_unlock_starting_biomes()
	for def in biomes.biomes:
		biome_vms[def.key] = BiomeViewModel.new(def.key, def)

	for node in nodes.mycelium_nodes:
		var mycelium_data = MyceliumNodeData.new(player_data, node)
		mycelium_node_data.append(mycelium_data)
		mycelium_node_vms.append(MyceliumNodeViewModel.new(player_data, mycelium_data))
		_track_manual_count(node)

	screens_data = ScreensData.new(screens.screens, screens.initial_screen)
	screens_vm = ScreensViewModel.new(screens_data)

	offline_income_vm = OfflineIncomeViewModel.new()

	tick_timer = Timer.new()
	tick_timer.wait_time = 10.0
	tick_timer.autostart = true
	tick_timer.timeout.connect(func() -> void:
		handle_tick()
	)
	add_child(tick_timer)

## Recursively loads every UpgradeDef .tres under path (other resource types
## in the tree, e.g. UpgradeEffect / ScalingSource, are skipped).
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
			# Exported/packed builds list resources as "<name>.tres.remap" —
			# the real resource lives at the path with ".remap" stripped.
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

func handle_tick() -> void:
	player_data.tick_count += 1
	for i in range(nodes.mycelium_nodes.size() -1, -1, -1):
		var node := mycelium_node_vms[i]._mycelium_data._node
		var node_change = node.auto_nodes.add(BigNumber.from_value(node.manual_nodes))
		node_change = node_change.mul(node_production_bonus(StringName(str(node.node_id))))
		if i != 0:
			mycelium_node_vms[i-1]._mycelium_data._node.auto_nodes = \
			mycelium_node_vms[i-1]._mycelium_data._node.auto_nodes.add(node_change)
		else:
			player_data.nutrients = player_data.nutrients.add(node_change)

func can_prestige() -> bool:
	if not biomes_data.is_unlocked(&"permafrost"):
		return false
	return preview_biomass_gain().gt(BigNumber.new(0.0, 0))

## Any upgrade in any system (symbiosis, biome upgrades, perks) that targets
## the &"node_production" stat for this node contributes here automatically —
## no per-upgrade wiring needed when a new one is added. Shared by the tick
## loop and the display VMs so they can never drift out of sync.
func node_production_bonus(node_id: StringName) -> BigNumber:
	var bonus := upgrade_system.modify(&"node_production", BigNumber.from_value(1.0),
		resolve_context, [], node_id)
	bonus = biome_upgrade_system.modify(&"node_production", bonus, resolve_context, [], node_id)
	bonus = prestige_upgrade_system.modify(&"node_production", bonus, resolve_context, [], node_id)
	return bonus

## Any upgrade in any system (biome upgrades, perks) that targets the
## &"biomass_gain" stat contributes here automatically — no per-upgrade
## wiring needed when a new one is added.
func preview_biomass_gain() -> BigNumber:
	var gain := PrestigeCalculator.calculate_biomass_gain(player_data.tick_count, player_data.nutrients)
	gain = biome_upgrade_system.modify(&"biomass_gain", gain, resolve_context)
	gain = prestige_upgrade_system.modify(&"biomass_gain", gain, resolve_context)
	return gain

## Resets the current run (nutrients, water, tick_count, node purchases,
## symbiosis upgrades, biome unlocks) and converts it into biomass. Biome
## upgrades and prestige_upgrade_system are untouched — they persist across
## prestiges.
func prestige() -> void:
	var biomass_gain := preview_biomass_gain()
	player_data.biomass = player_data.biomass.add(biomass_gain)
	player_data.nutrients = BigNumber.from_value(1.0)
	player_data.water = BigNumber.from_value(0.0)
	player_data.tick_count = 0
	player_data.prestige_count += 1

	for node in nodes.mycelium_nodes:
		node.manual_nodes = 0 if node.node_id != 0 else 1
		node.auto_nodes = BigNumber.new(0.0, 0)

	upgrade_system.reset()
	biome_upgrade_system.reset()

	biomes_data.reset()
	_unlock_starting_biomes()

func _unlock_starting_biomes() -> void:
	for def in biomes.biomes:
		if def.always_unlocked:
			biomes_data.unlock(def.key)

# ---------------------------------------------------------------- biomes

## Gates bottom-bar tab visibility only. Once a biome has ever been unlocked,
## its screen stays reachable across prestige resets — feature access inside
## that screen (buying, etc.) is gated separately on biomes_data.is_unlocked.
func is_screen_unlocked(screen_type: int) -> bool:
	if screen_type == ScreenTypes.Types.BIOMES:
		return true
	var def := biome_def_for_screen(screen_type)
	return def == null or biomes_data.is_ever_unlocked(def.key)

func biome_def(key: StringName) -> BiomeDef:
	for def in biomes.biomes:
		if def.key == key:
			return def
	return null

func biome_def_for_screen(screen_type: int) -> BiomeDef:
	for def in biomes.biomes:
		if def.screen_type == screen_type:
			return def
	return null

func biome_xp(key: StringName) -> int:
	var def := biome_def(key)
	return BiomeCalculator.xp_for(def) if def else 0

func biome_level(key: StringName) -> Dictionary:
	return BiomeCalculator.level_for(biome_xp(key))

func biome_available_points(key: StringName) -> int:
	var lvl: int = biome_level(key).level
	return max(0, lvl - 1 - biomes_data.points_spent(key))

func can_unlock_biome(key: StringName) -> bool:
	var def := biome_def(key)
	if def == null or biomes_data.is_unlocked(key):
		return false
	var currency: BigNumber = player_data.get(_currency_field(def.unlock_currency))
	return currency.gte(def.unlock_cost)

func unlock_biome(key: StringName) -> bool:
	if not can_unlock_biome(key):
		return false
	var def := biome_def(key)
	var field := _currency_field(def.unlock_currency)
	var current: BigNumber = player_data.get(field)
	player_data.set(field, current.sub(def.unlock_cost))
	biomes_data.unlock(key)
	return true

## Each biome currently ships exactly one upgrade, bought with that biome's
## own level points. Add more by extending this map alongside new .tres defs
## under data/upgrades/biomes/<key>/.
func biome_upgrade_id(key: StringName) -> StringName:
	match key:
		&"forest": return &"DenseMycelium"
		&"symbiosis": return &"SymbioticBloom"
		&"permafrost": return &"FrozenSpores"
		_: return &""

func biome_upgrade_name(key: StringName) -> String:
	match key:
		&"forest": return "Dense Mycelium"
		&"symbiosis": return "Symbiotic Bloom"
		&"permafrost": return "Frozen Spores"
		_: return ""

func buy_biome_upgrade(id: StringName, key: StringName) -> bool:
	if biome_available_points(key) < 1:
		return false
	# Spend before buying: buy_with_points emits upgrades_changed synchronously,
	# and views refresh points_spent() off that same signal — emitting before
	# the spend landed showed the old (pre-purchase) point count until
	# something else happened to trigger a second refresh.
	biomes_data.spend_points(key, 1)
	if not biome_upgrade_system.buy_with_points(id, 1):
		biomes_data.spend_points(key, -1)  # refund: def had no room left to level
		return false
	return true

# ---------------------------------------------------------------- perks

func perk_def(id: StringName) -> PerkDef:
	return perk_defs.get(id)

## "owned" (level > 0), "available" (parent owned, this isn't maxed), or
## "locked" (parent not yet owned).
func perk_status(id: StringName) -> String:
	var def := perk_def(id)
	if def == null:
		return "locked"
	if prestige_upgrade_system.level(id) > 0:
		return "owned"
	if def.parent_id == &"" or prestige_upgrade_system.level(def.parent_id) > 0:
		return "available"
	return "locked"

func can_buy_perk(id: StringName) -> bool:
	if perk_status(id) == "locked":
		return false
	return prestige_upgrade_system.can_buy(id, player_data.biomass)

func buy_perk(id: StringName) -> bool:
	if not can_buy_perk(id):
		return false
	return prestige_upgrade_system.buy(id, player_data, &"biomass")

func _currency_field(currency: CurrencyTypes.Types) -> StringName:
	match currency:
		CurrencyTypes.Types.WATER:
			return &"water"
		CurrencyTypes.Types.BIOMASS:
			return &"biomass"
		_:
			return &"nutrients"
