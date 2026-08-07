extends Node
## Autoload (Project Settings > Globals). Save that survives the game dying at
## any moment: clean quit, crash, power loss or OS suspend on mobile.

const SAVE_PATH   := "user://save.json"
const BACKUP_PATH := "user://save.bak.json"
const TMP_PATH    := "user://save.tmp.json"
const SAVE_VERSION := 6

## The three UpgradeSystem buckets in a save, for migrations that touch all of
## them. Order is irrelevant, each is keyed independently.
const UPGRADE_BUCKETS: Array[String] = ["upgrades", "biome_upgrades", "prestige_upgrades"]

## v1 -> v2: perk ids went from "<branch key><roman numeral>" to the authored
## PerkNodeDef.id. Without this remap UpgradeSystem.from_save() drops every perk
## level as unknown.
const PERK_IDS_V1_TO_V2 := {
	"nutI": "substrate_1", "nutII": "substrate_2",
	"nutIII·A": "substrate_3a", "nutIII·B": "substrate_3b",
	"nutIV·A": "substrate_4a", "nutIV·B": "substrate_4b",
	"bioI": "fruiting_1", "bioII": "fruiting_2",
	"bioIII·A": "fruiting_3a", "bioIII·B": "fruiting_3b",
	"bioIV·A": "fruiting_4a", "bioIV·B": "fruiting_4b",
	"tmpI": "tempo_1", "tmpII": "tempo_2",
	"tmpIII·A": "tempo_3a", "tmpIII·B": "tempo_3b",
	"tmpIV·A": "tempo_4a", "tmpIV·B": "tempo_4b",
	"bntI": "bounty_1", "bntII": "bounty_2",
	"bntIII·A": "bounty_3a", "bntIII·B": "bounty_3b",
	"bntIV·A": "bounty_4a", "bntIV·B": "bounty_4b",
}
const AUTOSAVE_INTERVAL := 15.0  # seconds
const OFFLINE_CALC_FRAME_BUDGET_MSEC := 20.0  # yield to a frame once a batch exceeds this

## Emitted when offline progress becomes pending outside of load_game(), i.e. on
## app resume, so a live main_screen can react without a reload.
signal offline_progress_pending

var last_savegame: Dictionary
var _pending_offline_saved_at := 0.0
var _offline_calc_running := false

## Wall clock, injectable so the offline gap logic can be exercised without
## sleeping through a real one.
var now_provider: Callable = func() -> float: return Time.get_unix_time_from_system()

func _now() -> float:
	return float(now_provider.call())

func _ready() -> void:
	# Run our own logic before the window closes.
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
		NOTIFICATION_APPLICATION_FOCUS_OUT: # mobile, may get killed after this
			save_game()
		NOTIFICATION_APPLICATION_RESUMED, \
		NOTIFICATION_APPLICATION_FOCUS_IN:
			_arm_offline_progress(float(last_savegame.get("saved_at", 0.0)), true)
# ---------------------------------------------------------------- save

func save_game() -> void:
	var data := {
		"version": SAVE_VERSION,
		"saved_at": _now(),  # for offline progress
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
	f = null  # release the handle before the rename below

	# 2. Rotate the current good save to backup. A failure here is not fatal - the
	# write below still lands - but it leaves the backup stale, and that is the
	# file load_game() falls back to when the primary turns up corrupt, so it must
	# not pass silently.
	if FileAccess.file_exists(SAVE_PATH):
		var backup_error := DirAccess.copy_absolute(SAVE_PATH, BACKUP_PATH)
		if backup_error != OK:
			push_warning("Could not refresh %s (error %d), the backup is now stale." % [BACKUP_PATH, backup_error])

	# 3. Replace the real file with the temp. If this fails the on-disk save is
	# still the previous one, so last_savegame must not advance: offline progress
	# is measured from its saved_at, and claiming a write that didn't land drops
	# everything since the last successful save.
	var rename_error := DirAccess.rename_absolute(TMP_PATH, SAVE_PATH)
	if rename_error != OK:
		push_error("Save failed: could not replace %s (error %d)" % [SAVE_PATH, rename_error])
		return

	last_savegame = data

# ---------------------------------------------------------------- load

func load_game() -> void:
	var data := _read(SAVE_PATH)
	if data.is_empty():
		data = _read(BACKUP_PATH)  # primary is missing or corrupt
	if data.is_empty():
		return  # fresh start

	if not _migrate(data):
		return

	_apply_data(data.get("game", {}))
	# Deferred: the catch-up loop is thousands of ticks at the 24h cap, enough to
	# block startup if run here. main_screen kicks it off once the offline income
	# screen checks for it, timesliced (see run_offline_progress_calculation()).
	_arm_offline_progress(float(data.get("saved_at", 0.0)), false)

## Brings an older save up to SAVE_VERSION in place and refuses one written by a
## newer build. Returns false if the save must not be applied. Add a migration
## step per version bump.
func _migrate(data: Dictionary) -> bool:
	var version := int(data.get("version", 0))
	if version > SAVE_VERSION:
		push_error("Save is version %d but this build only understands %d, refusing to load it rather than corrupt it." % [version, SAVE_VERSION])
		return false
	if version < SAVE_VERSION:
		push_warning("Migrating save from version %d to %d." % [version, SAVE_VERSION])
	# Version 0 (unversioned) and version 1 share a shape, so both start here.
	if version < 2:
		_migrate_perk_ids_to_v2(data)
	if version < 3:
		_migrate_lifetime_counters_to_v3(data)
	if version < 4:
		_migrate_lifetime_biome_size_to_v4(data)
	if version < 5:
		_migrate_lifetime_upgrade_levels_to_v5(data)
	if version < 6:
		_migrate_point_plan_to_sequences_v6(data)
	data["version"] = SAVE_VERSION
	return true

## Rewrites the prestige upgrade keys of a pre-v2 save in place. Keys not in the
## table (a perk added since, or an id already migrated) are left alone.
func _migrate_perk_ids_to_v2(data: Dictionary) -> void:
	if not data.has("game"):
		return
	var game: Dictionary = data["game"]
	var perks: Dictionary = game.get("prestige_upgrades", {})
	var migrated := {}
	for key in perks:
		migrated[PERK_IDS_V1_TO_V2.get(key, key)] = perks[key]
	game["prestige_upgrades"] = migrated

## Seeds the lifetime counters the achievement ladder measures, which pre-v3
## saves have no record of. Without this a veteran player's whole archive reads
## as untouched. Only the two that can be reconstructed are seeded: nutrients and
## crystals earned across past runs are simply not recorded anywhere.
func _migrate_lifetime_counters_to_v3(data: Dictionary) -> void:
	if not data.has("game"):
		return
	var game: Dictionary = data["game"]
	var player: Dictionary = game.get("player_data", {})
	player["lifetime_ticks"] = int(player.get("tick_count", 0))
	var nodes: Array = game.get("mycelium_nodes", [])
	var manual_total := 0
	# Untyped loop variable with a guard, not `for node: Dictionary in nodes`:
	# a migration runs against whatever is on disk, so it cannot assume the shape
	# is intact - see load_mycelium_node_data().
	for node: Variant in nodes:
		if not node is Dictionary:
			continue
		manual_total += int(node.get("manual_nodes", 0))
	player["lifetime_manual_nodes"] = manual_total
	game["player_data"] = player

## Seeds the lifetime Biome Size count, which used to be read off the current
## run's sizes instead of accumulated. Those sizes are the only record left, so
## they are the starting total: levels bought in runs already sporated away are
## simply not recorded anywhere.
func _migrate_lifetime_biome_size_to_v4(data: Dictionary) -> void:
	if not data.has("game"):
		return
	var game: Dictionary = data["game"]
	var player: Dictionary = game.get("player_data", {})
	var biomes: Dictionary = game.get("biomes", {})
	var sizes: Dictionary = biomes.get("size", {})
	var total := 0
	for key in sizes:
		total += int(sizes[key])
	player["lifetime_biome_size"] = total
	game["player_data"] = player

## Seeds each upgrade track's lifetime purchase count, which used to be read off
## the levels currently held. Those levels are the only record left, so they are
## the starting total: anything a past prestige reset away was never counted.
func _migrate_lifetime_upgrade_levels_to_v5(data: Dictionary) -> void:
	if not data.has("game"):
		return
	var game: Dictionary = data["game"]
	for bucket in UPGRADE_BUCKETS:
		var levels: Dictionary = game.get(bucket, {})
		if levels.is_empty():
			continue
		var total := 0
		for key in levels:
			if key == UpgradeSystem.LIFETIME_KEY:
				continue
			total += int(levels[key])
		levels[UpgradeSystem.LIFETIME_KEY] = total
		game[bucket] = levels

## Converts the old per-biome point plan, a list of {id, target} pairs, into the
## recorded sequence that replaced it, where a repeated id is how a level above
## one is expressed. A target of 0 meant "buy until maxed", which a sequence has
## no way to say, so it becomes a single step: better to under-record the
## player's intent than to spend points they never allocated.
func _migrate_point_plan_to_sequences_v6(data: Dictionary) -> void:
	if not data.has("game"):
		return
	var game: Dictionary = data["game"]
	var automation: Dictionary = game.get("automation", {})
	if not automation.has("point_plan"):
		return
	var plans: Dictionary = automation["point_plan"]
	var sequences: Dictionary = automation.get("upgrade_sequences", {})
	for biome_key in plans:
		var steps: Array = []
		for entry: Variant in plans[biome_key]:
			if not entry is Dictionary:
				continue   # same reason as the v3 migration above
			var id: String = str(entry.get("id", ""))
			if id.is_empty():
				continue
			for i in range(maxi(1, int(entry.get("target", 0)))):
				steps.append(id)
		if not steps.is_empty():
			sequences[biome_key] = steps
	automation["upgrade_sequences"] = sequences
	automation.erase("point_plan")
	game["automation"] = automation

func _read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var text := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	return parsed if parsed is Dictionary else {}

# ---------------------------------------------------------------- offline

## Records the timestamp a later catch-up measures from and optionally tells a
## live main_screen about it. Android sends both APPLICATION_RESUMED and FOCUS_IN
## per resume, plus FOCUS_IN at app start, so this must be idempotent.
##
## Two things it deliberately refuses to do:
##   * arm while a catch-up is running. That run owns the gap (it zeroes
##     _pending_offline_saved_at up front), so re-arming from the pre-resume
##     saved_at replays the whole gap and spawns a second popup.
##   * keep a gap too short to be shown. A stale sub-threshold timestamp would
##     cross the minimum as wall-clock advances and turn a later refresh into a
##     bogus mid-session catch-up.
func _arm_offline_progress(saved_at: float, notify: bool) -> void:
	if _offline_calc_running:
		return
	if saved_at <= 0.0:
		return  # nothing saved yet this session, don't clobber an armed gap with 0
	if not OfflineProgress.is_gap_worth_showing(_now() - saved_at):
		_pending_offline_saved_at = 0.0
		return
	_pending_offline_saved_at = saved_at
	if notify:
		offline_progress_pending.emit()

## Whether a catch-up loop is mid-flight, so callers don't stack a second one.
func is_offline_calc_running() -> bool:
	return _offline_calc_running

## True once there's an unprocessed offline gap worth simulating. Cheap enough
## for main_screen to poll without triggering work.
func has_pending_offline_progress() -> bool:
	if _pending_offline_saved_at <= 0.0:
		return false
	return OfflineProgress.is_gap_worth_showing(_now() - _pending_offline_saved_at)

## Runs the offline catch-up tick loop, timesliced across frames so it never
## holds one long enough to drop below 30fps (33ms/frame, we yield well before
## that at OFFLINE_CALC_FRAME_BUDGET_MSEC). Call once the offline income screen
## is ready to consume the result. Populates App.offline_income_vm when done,
## which is what triggers the popup.
func run_offline_progress_calculation() -> void:
	if _offline_calc_running or not has_pending_offline_progress():
		return
	_offline_calc_running = true
	var saved_at := _pending_offline_saved_at
	_pending_offline_saved_at = 0.0
	App.offline_income_vm.set_calculating(true)

	# Measured once. Reading the clock again at the end instead would report a
	# gap that includes every frame this loop awaited, so the popup would claim
	# more offline time than it actually simulated ticks for.
	var elapsed := OfflineProgress.capped(_now() - saved_at)

	# Only the endpoints are read (the popup diffs snapshot[0] against
	# snapshot[-1]), so nothing is captured mid-loop. _collect_data() serializes
	# player data, every node and all three upgrade systems, which per tick would
	# dominate the catch-up loop for no visible result.
	var save_game_snapshots: Array[Dictionary]
	save_game_snapshots.append(_collect_data())

	# One count drives the loop and the progress bar, so "done" always lands on
	# "total" rather than one tick short of it.
	var total_ticks := OfflineProgress.simulated_ticks(elapsed, App.tick_timer.wait_time)
	App.offline_income_vm.set_calc_progress(0, total_ticks)

	# The real-time tick timer must not fire while handle_tick() is driven
	# manually below, or ticks double up across the awaited frames.
	App.tick_timer.stop()
	# Automations only act while the player is actually playing. They ride on
	# handle_tick(), so without this the loop below would let them spend a whole
	# night's ticks in one burst.
	App.automations_running = false
	# Nothing here buys anything, so upgrade levels and manual node counts are
	# fixed for the loop and the per-node bonus is invariant. Compute it once
	# instead of ~9 modify() calls per node per tick.
	var bonuses := App.node_production_bonuses()
	var batch_start := Time.get_ticks_msec()
	for tick_counter in range(1, total_ticks + 1):
		App.handle_tick(bonuses)

		if Time.get_ticks_msec() - batch_start >= OFFLINE_CALC_FRAME_BUDGET_MSEC:
			App.offline_income_vm.set_calc_progress(tick_counter, total_ticks)
			await get_tree().process_frame
			batch_start = Time.get_ticks_msec()
	App.tick_timer.start()
	App.automations_running = true

	# final snapshot after tick accumulation
	save_game_snapshots.append(_collect_data())

	App.offline_income_vm.set_save_data(save_game_snapshots, total_ticks, elapsed)
	App.offline_income_vm.set_calculating(false)
	save_game()
	_offline_calc_running = false

# ---------------------------------------------------------------- hooks

func _collect_data() -> Dictionary:
	var save_state := {
		"player_data": App.player_data.to_save(),
		"mycelium_nodes": get_mycelium_node_data(),
		"upgrades": App.upgrade_system.to_save(),
		"prestige_upgrades": App.prestige_upgrade_system.to_save(),
		"biomes": App.biomes_data.to_save(),
		"biome_upgrades": App.biome_upgrade_system.to_save(),
		"achievements": App.achievement_progress.to_save(),
		"automation": App.automation_data.to_save(),
		"geode_upgrades": App.geode_upgrade_system.to_save()
	}
	return save_state

func _apply_data(game: Dictionary) -> void:
	App.player_data.load_from_save(game.get("player_data", {}))
	load_mycelium_node_data(game.get("mycelium_nodes", []))
	App.upgrade_system.from_save(game.get("upgrades", {}))
	App.prestige_upgrade_system.from_save(game.get("prestige_upgrades", {}))
	App.biomes_data.load_from_save(game.get("biomes", {}))
	App.resolve_context.biome_sizes = App.biomes_data.size.duplicate()
	App.biome_upgrade_system.from_save(game.get("biome_upgrades", {}))
	App.achievement_progress.load_from_save(game.get("achievements", {}))
	# PlayerData.achievement_tiers is a projection of the progress just loaded,
	# not a saved field, so it has to be rebuilt here.
	App.achievement_system.sync_tier_count()
	App.automation_data.load_from_save(game.get("automation", {}))
	App.geode_upgrade_system.from_save(game.get("geode_upgrades", {}))

func get_mycelium_node_data() -> Array[Dictionary]:
	var all_node_data: Array[Dictionary] = []
	for node_data in App.mycelium_node_data:
		all_node_data.append({
			"manual_nodes": node_data.node.manual_nodes,
			"auto_nodes": node_data.node.auto_nodes.to_save()
		})
	return all_node_data

## Entries that are not Dictionaries are skipped rather than assigned: the typed
## local below would take the whole load down on a corrupt save, which is the one
## path that has to degrade instead. A skipped tier keeps its fresh-start values.
func load_mycelium_node_data(nodes: Array) -> void:
	for i in range(App.mycelium_node_data.size()):
		if i < nodes.size():
			if not nodes[i] is Dictionary:
				push_warning("Save entry for mycelium node %d is not a Dictionary, skipping it." % i)
				continue
			var node_data := App.mycelium_node_data[i]
			var loaded_data: Dictionary = nodes[i]
			node_data.node.manual_nodes = loaded_data.get("manual_nodes", 0)
			node_data.node.auto_nodes = BigNumber.from_save(loaded_data.get("auto_nodes", {}))
