extends Node
## Autoload (Project Settings > Globals). Robust save for a game that can die
## at any moment: clean quit, crash, power loss, or OS suspend on mobile.

const SAVE_PATH   := "user://save.json"
const BACKUP_PATH := "user://save.bak.json"
const TMP_PATH    := "user://save.tmp.json"
const SAVE_VERSION := 1
const AUTOSAVE_INTERVAL := 15.0  # seconds
const MIN_OFFLINE_SECONDS := 60.0
const MAX_OFFLINE_SECONDS := 86400.0  # 24h cap on offline income collection
const OFFLINE_CALC_FRAME_BUDGET_MSEC := 20.0  # yield to a frame once a batch exceeds this

## Emitted when offline progress becomes newly pending outside of load_game()
## (i.e. on app resume), so a live main_screen can react without a reload.
signal offline_progress_pending

var last_savegame : Dictionary
var _pending_offline_saved_at := 0.0
var _offline_calc_running := false

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
			_pending_offline_saved_at = float(last_savegame.get("saved_at", 0.0))
			offline_progress_pending.emit()
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
	# Deferred: the offline catch-up loop is expensive (thousands of ticks for
	# the 24h cap) and used to run synchronously here, in the autoload's own
	# _ready(), blocking the game from starting at all. It's now kicked off
	# by main_screen once the offline income screen actually checks for it,
	# and timesliced across frames (see run_offline_progress_calculation()).
	_pending_offline_saved_at = float(data.get("saved_at", 0.0))

func _read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var text := FileAccess.get_file_as_string(path)
	var parsed = JSON.parse_string(text)
	return parsed if parsed is Dictionary else {}

# ---------------------------------------------------------------- offline

## True once there's an unprocessed offline gap worth simulating. Cheap check
## so callers (main_screen) can poll it without triggering any work.
func has_pending_offline_progress() -> bool:
	if _pending_offline_saved_at <= 0.0:
		return false
	var elapsed := Time.get_unix_time_from_system() - _pending_offline_saved_at
	return elapsed > MIN_OFFLINE_SECONDS

## Runs the offline catch-up tick loop, timesliced across frames so it never
## holds a single frame long enough to drop below 30fps (~33ms/frame — we
## yield well before that, at OFFLINE_CALC_FRAME_BUDGET_MSEC). Call this once
## the offline income screen is ready to consume the result; it populates
## App.offline_income_vm when done, which is what actually triggers the popup.
func run_offline_progress_calculation() -> void:
	if _offline_calc_running or not has_pending_offline_progress():
		return
	_offline_calc_running = true
	var saved_at := _pending_offline_saved_at
	_pending_offline_saved_at = 0.0
	App.offline_income_vm.set_calculating(true)

	var elapsed := minf(Time.get_unix_time_from_system() - saved_at, MAX_OFFLINE_SECONDS)

	var save_game_snapshots: Array[Dictionary]
	# initial snapshot
	save_game_snapshots.append(_collect_data())

	# limit snapshots to a manageable amount
	var snapshot_interval: int = floor((elapsed/App.tick_timer.wait_time)/100)
	var total_ticks_expected: int = maxi(1, int(elapsed / App.tick_timer.wait_time))
	App.offline_income_vm.set_calc_progress(0, total_ticks_expected)

	var tick_counter = 0
	var snapshot_tick_counter = 0
	elapsed -= App.tick_timer.wait_time

	# The real-time tick timer must not fire while we're manually driving
	# handle_tick() below, or ticks would double up across the awaited frames.
	App.tick_timer.stop()
	var batch_start := Time.get_ticks_msec()
	while elapsed > 0.0:
		elapsed -= App.tick_timer.wait_time
		App.handle_tick()
		tick_counter += 1
		if snapshot_tick_counter >= snapshot_interval:
			save_game_snapshots.append(_collect_data())
			snapshot_tick_counter = 0
		else:
			snapshot_tick_counter += 1

		if Time.get_ticks_msec() - batch_start >= OFFLINE_CALC_FRAME_BUDGET_MSEC:
			App.offline_income_vm.set_calc_progress(tick_counter, total_ticks_expected)
			await get_tree().process_frame
			batch_start = Time.get_ticks_msec()
	App.tick_timer.start()

	# final snapshot after tick accumulation
	save_game_snapshots.append(_collect_data())

	App.offline_income_vm.set_save_data(save_game_snapshots, \
		tick_counter, minf(Time.get_unix_time_from_system() - saved_at, MAX_OFFLINE_SECONDS))
	App.offline_income_vm.set_calculating(false)
	save_game()
	_offline_calc_running = false

# ---------------------------------------------------------------- hooks

func _collect_data() -> Dictionary:
	var save_state = {
		"player_data": App.player_data.to_save(),
		"mycelium_nodes": get_mycelium_node_data(),
		"upgrades": App.upgrade_system.to_save(),
		"prestige_upgrades": App.prestige_upgrade_system.to_save(),
		"biomes": App.biomes_data.to_save(),
		"biome_upgrades": App.biome_upgrade_system.to_save()
	}
	return save_state

func _apply_data(_game: Dictionary) -> void:
	App.player_data.load_from_save(_game.get("player_data", {}))
	load_mycelium_node_data(_game.get("mycelium_nodes", []))
	App.upgrade_system.from_save(_game.get("upgrades", {}))
	App.prestige_upgrade_system.from_save(_game.get("prestige_upgrades", {}))
	var loaded_biomes_data := BiomesData.from_save(_game.get("biomes", {}))
	# ever_unlocked must be restored directly, not via unlock(), which would
	# also mark the biome unlocked for the current run.
	for key in loaded_biomes_data.ever_unlocked:
		App.biomes_data.ever_unlocked[key] = true
	for key in loaded_biomes_data.unlocked:
		App.biomes_data.unlock(key)
	App.biomes_data.spent_points = loaded_biomes_data.spent_points
	App.biomes_data.size = loaded_biomes_data.size
	App.resolve_context.biome_sizes = App.biomes_data.size.duplicate()
	App.biome_upgrade_system.from_save(_game.get("biome_upgrades", {}))

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
