class_name MissionSlotViewModel
extends ViewModel
## VIEWMODEL: one place on one of the two boards - what is in it, how far along,
## and what the one button on it does.
## Owns formatting, derived state and enabled/disabled logic.
## References the model, never a Node.
##
## The slot is the unit on screen, not the mission. The board has a handful of
## places and the ladder has dozens of missions, so a screen built out of missions
## makes the player hunt for the two or three they can act on; a screen built out
## of slots shows the whole of what is happening in as many rows as there are
## places, and sends the hunting to a chooser they open on purpose.
##
## A slot is addressed by its index into the board, and reads whatever is in that
## index right now. Collecting the first of three expeditions shifts the other two
## up a place, which is why the cards repaint on active_changed rather than
## holding an instance id of their own.
##
## One per index per kind, cached on App and grown as the boards widen.

const PROP_SLOT_CHANGED := &"slot_changed"
## The wall clock moved and nothing in the model fired to say so. Split from the
## above for the reason MissionViewModel splits it: the panel polls once a second
## and rebuilding a card that often would fight the player's finger.
const PROP_CLOCK_MOVED := &"clock_moved"

var _index: int
var _is_farm: bool

# --- View -> ViewModel ---

## The one button. Collects a finished expedition, or takes a creature off a
## farm. An empty slot has no command here - the panel opens the chooser instead,
## because picking a mission is a choice and this is a press.
func act() -> bool:
	var entry := _entry()
	if entry.is_empty():
		return false
	if _is_farm:
		return App.stop_farm(int(entry["instance_id"]))
	return App.collect_mission(int(entry["instance_id"]))

# --- Read-only display properties bound by the View ---

var index: int:
	get: return _index

var is_farm: bool:
	get: return _is_farm

var is_filled: bool:
	get: return not _entry().is_empty()

var mission_name: String:
	get:
		var def := _mission_def()
		if def != null:
			return def.display_name
		return "Free plot" if _is_farm else "Empty slot"

var creature_name: String:
	get:
		var entry := _entry()
		if entry.is_empty():
			return ""
		var creature := App.creature_def(entry["creature_id"])
		return creature.display_name if creature != null else ""

var is_complete: bool:
	get: return not _is_farm and App.is_mission_complete(_entry())

var progress_ratio: float:
	get:
		var entry := _entry()
		if entry.is_empty():
			return 0.0
		if _is_farm:
			return App.farm_progress_ratio(entry)
		return App.mission_progress_ratio(entry)

## The line beside the bar. A finished expedition says so in a word; a farm
## counts down the cycle in progress, which never ends.
var countdown_text: String:
	get:
		var entry := _entry()
		if entry.is_empty():
			return ""
		if not _is_farm and App.is_mission_complete(entry):
			return "Ready"
		return _duration_text(App.mission_seconds_remaining(entry))

## What this slot is paying, from the snapshot taken when it was filled - the
## number the chooser promised is the number that keeps being shown.
var reward_text: String:
	get:
		var entry := _entry()
		if entry.is_empty():
			return ""
		var parts: PackedStringArray = []
		for payout: Dictionary in entry["payouts"]:
			var amount := BigNumber.new(float(payout["m"]), int(payout["e"]))
			parts.append("%s %s" % [amount.to_display(),
				CurrencyTypes.display_name_for(int(payout["currency"]) as CurrencyTypes.Types)])
		var line := ", ".join(parts)
		if _is_farm and not line.is_empty():
			return "%s every %s" % [line, _duration_text(float(entry["duration"]))]
		return line

## The permanent upgrade this expedition will grant, so what is being worked
## towards is readable without opening anything.
var boon_text: String:
	get:
		var def := _mission_def()
		if def == null or _is_farm:
			return ""
		return EffectLabel.of_effects(def.rewards)

var action_text: String:
	get:
		if not is_filled:
			return "Assign +" if _is_farm else "Send +"
		return "Stop" if _is_farm else "Collect"

## Whether the button does anything. A farm can always be stopped; an expedition
## can only be collected once it is back.
var can_act: bool:
	get:
		if not is_filled:
			return false
		return true if _is_farm else is_complete

# --- Lifecycle ---

func _init(index: int, is_farm: bool) -> void:
	_index = index
	_is_farm = is_farm
	App.ruins_data.active_changed.connect(_on_changed)
	App.ruins_data.creatures_changed.connect(_on_changed)
	# Both tracks can widen the board, and either can be bought from another
	# screen while this one is open.
	App.mission_upgrade_system.upgrades_changed.connect(_on_changed)
	App.prestige_upgrade_system.upgrades_changed.connect(_on_changed)
	App.expedition_upgrade_system.upgrades_changed.connect(_on_changed)
	# Losing the Ruins to a sporation stops the board, which every slot shows.
	App.biomes_data.biome_unlocked.connect(_on_changed.unbind(1))

func dispose() -> void:
	App.ruins_data.active_changed.disconnect(_on_changed)
	App.ruins_data.creatures_changed.disconnect(_on_changed)
	App.mission_upgrade_system.upgrades_changed.disconnect(_on_changed)
	App.prestige_upgrade_system.upgrades_changed.disconnect(_on_changed)
	App.expedition_upgrade_system.upgrades_changed.disconnect(_on_changed)
	App.biomes_data.biome_unlocked.disconnect(_on_changed.unbind(1))

## Driven by the Ruins panel's one-second timer, not by a model signal: nothing
## in the model moves as a mission counts down. See RuinsViewModel.
func notify_clock_moved() -> void:
	_notify(PROP_CLOCK_MOVED)

# --- Model -> notification plumbing ---

func _on_changed() -> void:
	_notify(PROP_SLOT_CHANGED)

# --- Reading the board ---

func _entry() -> Dictionary:
	var board := App.active_farms() if _is_farm else App.active_expeditions()
	if _index < 0 or _index >= board.size():
		return {}
	return board[_index]

func _mission_def() -> MissionDef:
	var entry := _entry()
	if entry.is_empty():
		return null
	return App.mission_def(entry["mission_id"])

## Coarse above a minute for the reason MissionViewModel's copy is: an errand
## counted to the second reads as a thing to sit and watch, which is the opposite
## of what the board is for.
func _duration_text(seconds: float) -> String:
	var total := int(ceil(maxf(0.0, seconds)))
	if total < 60:
		return "%ds" % total
	if total < 3600:
		@warning_ignore("integer_division")
		return "%dm %02ds" % [total / 60, total % 60]
	@warning_ignore("integer_division")
	return "%dh %02dm" % [total / 3600, (total % 3600) / 60]
