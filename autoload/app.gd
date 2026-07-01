extends Node
## AUTOLOAD "App" — the composition root.
## Owns the Models and ViewModels for the app's lifetime.
## Register in Project Settings > Autoload as "App".
##
## Models and VMs are RefCounted, so this autoload holding references
## is what keeps them alive. Views come and go with the scene tree.

var player_data: PlayerData
var player_vm: PlayerViewModel

func _ready() -> void:
	player_data = PlayerData.new()
	player_vm = PlayerViewModel.new(player_data)

	# Demo: passive income tick. In a real project this lives in a
	# dedicated system, but it shows the flow: mutate MODEL only,
	# and the VM/View update through signals automatically.
	var timer := Timer.new()
	timer.wait_time = 10.0
	timer.autostart = true
	timer.timeout.connect(func() -> void:
		player_data.gold += 1.0 + player_data.upgrade_level * 2.0
	)
	add_child(timer)
