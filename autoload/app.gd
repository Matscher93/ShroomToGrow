extends Node
## AUTOLOAD "App" — the composition root.
## Owns the Models and ViewModels for the app's lifetime.
## Register in Project Settings > Autoload as "App".
##
## Models and VMs are RefCounted, so this autoload holding references
## is what keeps them alive. Views come and go with the scene tree.

var player_data: PlayerData
var player_vm: PlayerViewModel
var mycelium_node_data: Array[MyceliumData]
var mycelium_node_vms: Array[MyceliumNodeViewModel]
var nodes := load("res://data/mycelium_nodes/res_all_mycelium_nodes.tres") as MyceliumNodes
var screens_data: ScreensData
var screens_vm: ScreensViewModel
var screens := load("res://data/screens/all_screens.tres") as Screens

var offline_income_vm: OfflineIncomeViewModel
var tick_timer: Timer

var upgrade_system: UpgradeSystem
var resolve_context := ResolveContext.new()

const UPGRADES_PATH := "res://data/upgrades/"

func _ready() -> void:
	player_data = PlayerData.new()
	player_vm = PlayerViewModel.new(player_data)

	upgrade_system = UpgradeSystem.new()
	for def in _load_upgrade_defs(UPGRADES_PATH):
		upgrade_system.register(def)

	for node in nodes.mycelium_nodes:
		var mycelium_data = MyceliumData.new(player_data, node)
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
		elif file_name.ends_with(".tres"):
			var res := load(full_path)
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
	player_data.tick_count += 1;
	for i in range(nodes.mycelium_nodes.size() -1, -1, -1):
		var node := mycelium_node_vms[i]._mycelium_data._node
		var node_change = node.auto_nodes.add(BigNumber.from_value(node.manual_nodes))
		var bonus := upgrade_system.modify(&"node_production", 1.0, resolve_context,
			[], StringName(str(node.node_id)))
		node_change = node_change.scale(bonus)
		if i != 0:
			mycelium_node_vms[i-1]._mycelium_data._node.auto_nodes = \
			mycelium_node_vms[i-1]._mycelium_data._node.auto_nodes.add(node_change)
		else:
			player_data.nutrients = player_data.nutrients.add(node_change)
