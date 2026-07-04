extends Node
## AUTOLOAD "App" — the composition root.
## Owns the Models and ViewModels for the app's lifetime.
## Register in Project Settings > Autoload as "App".
##
## Models and VMs are RefCounted, so this autoload holding references
## is what keeps them alive. Views come and go with the scene tree.

var player_data: PlayerData
var mycelium_nodes_vm: MyceliumNodesViewModel
var tick_timer: Timer
var nodes := load("res://data/mycelium_nodes/res_all_mycelium_nodes.tres") as MyceliumNodes

func _ready() -> void:
	player_data = PlayerData.new()
	player_data.nodes = nodes.mycelium_nodes
	mycelium_nodes_vm = MyceliumNodesViewModel.new(player_data)

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
		var node_change = mycelium_nodes_vm._model.nodes[i].auto_nodes + mycelium_nodes_vm._model.nodes[i].manual_nodes
		if i != 0:
			mycelium_nodes_vm._model.nodes[i - 1].auto_nodes = mycelium_nodes_vm._model.nodes[i - 1].auto_nodes + node_change
		else:
			player_data.nutrients = player_data.nutrients.add(BigNumber.from_value(node_change))
