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

func _ready() -> void:
	player_data = PlayerData.new()
	player_vm = PlayerViewModel.new(player_data)
	
	for node in nodes.mycelium_nodes:
		var mycelium_data = MyceliumData.new(player_data, node)
		mycelium_node_data.append(mycelium_data)
		mycelium_node_vms.append(MyceliumNodeViewModel.new(player_data, mycelium_data))

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

func handle_tick() -> void:
	player_data.tick_count += 1;
	for i in range(nodes.mycelium_nodes.size() -1, -1, -1): 
		var node_change = mycelium_node_vms[i]._mycelium_data._node.auto_nodes.add(\
		 BigNumber.from_value(mycelium_node_vms[i]._mycelium_data._node.manual_nodes))
		if i != 0:
			mycelium_node_vms[i-1]._mycelium_data._node.auto_nodes = \
			mycelium_node_vms[i-1]._mycelium_data._node.auto_nodes.add(node_change)
		else:
			player_data.nutrients = player_data.nutrients.add(node_change)
