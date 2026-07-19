extends Node
## Autoload (Project Settings > Globals). Robust save for a game that can die
## at any moment: clean quit, crash, power loss, or OS suspend on mobile.

const SAVE_PATH   := "user://save.json"
const BACKUP_PATH := "user://save.bak.json"
const TMP_PATH    := "user://save.tmp.json"
const SAVE_VERSION := 1
const AUTOSAVE_INTERVAL := 15.0  # seconds
const MIN_OFFLINE_SECONDS := 60.0

var last_savegame : Dictionary

func _ready() -> void:
	# We want to run our own logic before the window closes.
	get_tree().set_auto_accept_quit(false)

	var t := Timer.new()
	t.wait_time = AUTOSAVE_INTERVAL
	t.timeout.connect(save_game)
	add_child(t)
	t.start()

	load_game()

func _notification(what: int) -> void:
	match what:
		NOTIFICATION_WM_CLOSE_REQUEST:      # desktop [X] / Alt-F4
			save_game()
			get_tree().quit()
		NOTIFICATION_WM_GO_BACK_REQUEST:    # Android back button
			save_game()
			get_tree().quit()
		NOTIFICATION_APPLICATION_PAUSED, \
		NOTIFICATION_APPLICATION_FOCUS_OUT: # mobile: may get killed after this
			save_game()
		NOTIFICATION_APPLICATION_RESUMED, \
		NOTIFICATION_APPLICATION_FOCUS_IN:
			_apply_offline_progress(float(last_savegame.get("saved_at", 0.0)))
# ---------------------------------------------------------------- save

func save_game() -> void:
	var data := {
		"version": SAVE_VERSION,
		"saved_at": Time.get_unix_time_from_system(),  # for offline progress
		"game": _collect_data(),
	}

	# 1. Write to a temp file and fully close it before touching the real one.
	var f := FileAccess.open(TMP_PATH, FileAccess.WRITE)
	if f == null:
		push_error("Save failed: %s" % FileAccess.get_open_error())
		return
	f.store_string(JSON.stringify(data))
	f.flush()
	f.close()
	f = null  # important — see the gotcha note below

	# 2. Rotate the current good save to backup.
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.copy_absolute(SAVE_PATH, BACKUP_PATH)

	# 3. Replace the real file with the temp (overwrites the existing file).
	DirAccess.rename_absolute(TMP_PATH, SAVE_PATH)
	
	last_savegame = data

# ---------------------------------------------------------------- load

func load_game() -> void:
	var data := _read(SAVE_PATH)
	if data.is_empty():
		data = _read(BACKUP_PATH)  # fall back if primary is missing/corrupt
	if data.is_empty():
		return  # fresh start

	_apply_data(data.get("game", {}))
	_apply_offline_progress(float(data.get("saved_at", 0.0)))

func _read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var text := FileAccess.get_file_as_string(path)
	var parsed = JSON.parse_string(text)
	return parsed if parsed is Dictionary else {}

# ---------------------------------------------------------------- offline

func _apply_offline_progress(saved_at: float) -> void:
	if saved_at <= 0.0:
		return
	var elapsed := Time.get_unix_time_from_system() - saved_at
	if elapsed <= MIN_OFFLINE_SECONDS:
		return
	
	var save_game_snapshots: Array[Dictionary]
	# initial snapshot
	save_game_snapshots.append(_collect_data())
	
	# limit snapshots to a managable amount
	var snapshot_interval: int = floor((elapsed/App.tick_timer.wait_time)/100)
	
	var tick_counter = 0
	var snapshot_tick_counter = 0
	elapsed -= App.tick_timer.wait_time
	while elapsed > 0.0:
		elapsed -= App.tick_timer.wait_time
		App.handle_tick()
		tick_counter += 1
		if snapshot_tick_counter >= snapshot_interval:
			save_game_snapshots.append(_collect_data())
			snapshot_tick_counter = 0
		else:
			snapshot_tick_counter += 1
	
	# final snapshot after tick accumulation
	save_game_snapshots.append(_collect_data())
	
	App.offline_income_vm.set_save_data(save_game_snapshots, \
		tick_counter, Time.get_unix_time_from_system() - saved_at)
	save_game()

# ---------------------------------------------------------------- hooks

func _collect_data() -> Dictionary:
	var save_state = {
		"player_data": App.player_data.to_save(),
		"mycelium_nodes": get_mycelium_node_data(),
		"upgrades": App.upgrade_system.to_save(),
		"prestige_upgrades": App.prestige_upgrade_system.to_save()
	}
	return save_state

func _apply_data(_game: Dictionary) -> void:
	var loaded_player_data = PlayerData.from_save(_game.get("player_data", PlayerData.new()))
	App.player_data.nutrients = loaded_player_data.nutrients
	App.player_data.water = loaded_player_data.water
	App.player_data.biomass = loaded_player_data.biomass
	App.player_data.tick_count = loaded_player_data.tick_count
	load_mycelium_node_data(_game.get("mycelium_nodes", []))
	App.upgrade_system.from_save(_game.get("upgrades", {}))
	App.prestige_upgrade_system.from_save(_game.get("prestige_upgrades", {}))

func get_mycelium_node_data() -> Array[Dictionary]:
	var all_node_data: Array[Dictionary] = []
	for node_data in App.mycelium_node_data:
		all_node_data.append({
			"manual_nodes": node_data._node.manual_nodes, 
			"auto_nodes": node_data._node.auto_nodes.to_save()
		})
	return all_node_data
	
func load_mycelium_node_data(_nodes: Array) -> void:
	for i in range(App.mycelium_node_data.size()):
		if(i < _nodes.size()):
			var node_data = App.mycelium_node_data[i]
			var loaded_data = _nodes[i]
			node_data._node.manual_nodes = loaded_data.get("manual_nodes", 0)
			node_data._node.auto_nodes = BigNumber.from_save(loaded_data.get("auto_nodes", BigNumber.new(0.0,0)))
