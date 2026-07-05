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
var tick_timer: Timer
var nodes := load("res://data/mycelium_nodes/res_all_mycelium_nodes.tres") as MyceliumNodes

func _ready() -> void:
	player_data = PlayerData.new()
	player_vm = PlayerViewModel.new(player_data)
	
	for node in nodes.mycelium_nodes:
		var mycelium_data = MyceliumData.new(player_data, node)
		mycelium_node_data.append(mycelium_data)
		mycelium_node_vms.append(MyceliumNodeViewModel.new(player_data, mycelium_data))
	# Demo: passive income tick. In a real project this lives in a
	# dedicated system, but it shows the flow: mutate MODEL only,
	# and the VM/View update through signals automatically.
	tick_timer = Timer.new()
	tick_timer.wait_time = 1.0
	tick_timer.autostart = true
	tick_timer.timeout.connect(func() -> void:
		handle_tick()
	)
	add_child(tick_timer)

func handle_tick() -> void:
	for i in range(nodes.mycelium_nodes.size() -1, -1, -1): 
		var node_change = mycelium_node_vms[i]._mycelium_data._node.auto_nodes.add(\
		 BigNumber.from_value(mycelium_node_vms[i]._mycelium_data._node.manual_nodes))
		if i != 0:
			mycelium_node_vms[i-1]._mycelium_data._node.auto_nodes = \
			mycelium_node_vms[i-1]._mycelium_data._node.auto_nodes.add(node_change)
		else:
			player_data.nutrients = player_data.nutrients.add(node_change)
