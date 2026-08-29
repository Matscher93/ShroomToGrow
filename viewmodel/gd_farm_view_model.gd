class_name FarmViewModel
extends ViewModel
## VIEWMODEL: one farm - whether it is being worked, by how many, and the two
## presses that change that.
## Owns formatting, derived state and enabled/disabled logic.
## References the model, never a Node.
##
## Every farm the player has opened has a row of its own, running or not. There is
## nothing to choose and nowhere to choose it: a farm at zero workers is simply a
## farm nobody is on, and the way to start it is to put somebody on it.
##
## That is what the stepper means at its bottom end. Stepping up from zero starts
## the farm; stepping the last worker off stops it. The model has no notion of an
## idle farm holding a plot, so neither does the row.
##
## One per authored farm, built once and owned by App.

const PROP_FARM_CHANGED := &"farm_changed"
## The wall clock moved and nothing in the model fired to say so. Split from the
## above because the panel polls once a second, and rebuilding a card that often
## would fight the player's finger.
const PROP_CLOCK_MOVED := &"clock_moved"

var _id: StringName
var _def: MissionDef

# --- View -> ViewModel ---

## Puts one more worker on. From zero that starts the farm, which is the only
## place a farm is ever started.
func add_worker() -> bool:
	var entry := _entry()
	if entry.is_empty():
		return App.start_farm(_id, 1) > 0
	return App.set_farm_workers(int(entry["instance_id"]), int(entry["workers"]) + 1)

## Takes one worker off. Taking the last one off stops the farm and frees its
## plot, rather than leaving an empty farm holding one.
func remove_worker() -> bool:
	var entry := _entry()
	if entry.is_empty():
		return false
	var here := int(entry["workers"])
	if here <= 1:
		return App.stop_farm(int(entry["instance_id"]))
	return App.set_farm_workers(int(entry["instance_id"]), here - 1)

# --- Read-only display properties bound by the View ---

var mission_id: StringName:
	get: return _id

var display_name: String:
	get: return _def.display_name

var description: String:
	get: return _def.description

## Whether this farm belongs on screen at all. A farm the player has not opened
## is a promise they cannot act on, and the expedition that opens it says so on
## its own row.
var is_visible: bool:
	get: return App.is_mission_unlocked(_id) or is_running

var is_running: bool:
	get: return not _entry().is_empty()

var workers: int:
	get:
		var entry := _entry()
		return int(entry["workers"]) if not entry.is_empty() else 0

var max_workers: int:
	get: return App.max_workers_per_farm(_id)

var workers_text: String:
	get: return "%d / %d workers" % [workers, max_workers]

var progress_ratio: float:
	get: return App.farm_progress_ratio(_entry())

## What one cycle pays and how long it takes, from the snapshot while it runs and
## from what starting it would take while it does not.
var reward_text: String:
	get:
		var entry := _entry()
		if entry.is_empty():
			var vm: MissionViewModel = App.mission_vms.get(_id)
			return "%s every %s" % [vm.reward_text(), vm.duration_text()] if vm != null else ""
		var parts: PackedStringArray = []
		for payout: Dictionary in entry["payouts"]:
			var amount := BigNumber.new(float(payout["m"]), int(payout["e"]))
			parts.append("%s %s" % [amount.to_display(),
				CurrencyTypes.display_name_for(int(payout["currency"]) as CurrencyTypes.Types)])
		return "%s every %s" % [", ".join(parts), _duration_text(float(entry["duration"]))]

var countdown_text: String:
	get:
		var entry := _entry()
		if entry.is_empty():
			return ""
		return _duration_text(App.mission_seconds_remaining(entry))

## One more worker needs somebody free, room on this farm, and - starting from
## zero - a free plot on the farm board.
var can_add_worker: bool:
	get:
		if not is_running:
			return App.can_start_farm(_id, 1)
		return workers < App.most_workers_available_for(_id, workers)

var can_remove_worker: bool:
	get: return is_running

## Why the farm is doing nothing, when it is. Empty while it is running or could
## simply be started.
var status_text: String:
	get:
		if is_running or can_add_worker:
			return ""
		if not App.is_parasitic_control_active():
			return "The ruins are sealed."
		if App.workers_idle() <= 0:
			return "No worker is free."
		return "Every plot is taken."

# --- Lifecycle ---

func _init(mission_id_value: StringName, def: MissionDef) -> void:
	_id = mission_id_value
	_def = def
	App.ruins_data.active_changed.connect(_on_changed)
	App.ruins_data.workers_changed.connect(_on_changed)
	App.ruins_data.expeditions_changed.connect(_on_changed)
	App.ruins_data.missions_completed_changed.connect(_on_changed.unbind(1))
	# A boost or a perk moves what this pays, how long it takes, how many plots
	# there are and how many workers one farm holds.
	App.mission_upgrade_system.upgrades_changed.connect(_on_changed)
	App.prestige_upgrade_system.upgrades_changed.connect(_on_changed)
	App.expedition_upgrade_system.upgrades_changed.connect(_on_changed)
	App.biomes_data.biome_unlocked.connect(_on_changed.unbind(1))

func dispose() -> void:
	App.ruins_data.active_changed.disconnect(_on_changed)
	App.ruins_data.workers_changed.disconnect(_on_changed)
	App.ruins_data.expeditions_changed.disconnect(_on_changed)
	App.ruins_data.missions_completed_changed.disconnect(_on_changed.unbind(1))
	App.mission_upgrade_system.upgrades_changed.disconnect(_on_changed)
	App.prestige_upgrade_system.upgrades_changed.disconnect(_on_changed)
	App.expedition_upgrade_system.upgrades_changed.disconnect(_on_changed)
	App.biomes_data.biome_unlocked.disconnect(_on_changed.unbind(1))

func notify_clock_moved() -> void:
	_notify(PROP_CLOCK_MOVED)

# --- Model -> notification plumbing ---

func _on_changed() -> void:
	_notify(PROP_FARM_CHANGED)

# --- Reading the board ---

func _entry() -> Dictionary:
	return App.ruins_data.find_by_mission(_id)

func _duration_text(seconds: float) -> String:
	var total := int(ceil(maxf(0.0, seconds)))
	if total < 60:
		return "%ds" % total
	if total < 3600:
		@warning_ignore("integer_division")
		return "%dm %02ds" % [total / 60, total % 60]
	@warning_ignore("integer_division")
	return "%dh %02dm" % [total / 3600, (total % 3600) / 60]
