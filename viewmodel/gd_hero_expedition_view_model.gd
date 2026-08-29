class_name HeroExpeditionViewModel
extends ViewModel
## VIEWMODEL: one hero's place on the expedition board - how far along its chain
## it is, what step is in front of it, and the one press that moves it.
## Owns formatting, derived state and enabled/disabled logic.
## References the model, never a Node.
##
## The hero is the unit on screen, not the slot and not the mission. A hero runs
## exactly one chain and a chain is walked in order, so at any moment there is
## precisely one thing each hero could be doing - which means the row can show it
## and the button can start it, with nothing to pick and nowhere to pick it.
##
## One per authored hero, built once and owned by App.

const PROP_EXPEDITION_CHANGED := &"expedition_changed"
## The wall clock moved and nothing in the model fired to say so. Split from the
## above because the panel polls once a second, and rebuilding a card that often
## would fight the player's finger.
const PROP_CLOCK_MOVED := &"clock_moved"

var _id: StringName
var _def: HeroDef

# --- View -> ViewModel ---

## The one button: brings a finished expedition home, or sends the hero on the
## next step of its chain. Which of the two it is, is what action_text says.
func act() -> bool:
	var entry := _entry()
	if not entry.is_empty():
		return App.collect_mission(int(entry["instance_id"]))
	var step := App.sendable_step(_id)
	if step.is_empty():
		return false
	return App.send_mission(step, _id) > 0

# --- Read-only display properties bound by the View ---

var hero_id: StringName:
	get: return _id

var display_name: String:
	get: return _def.display_name

## Whether this hero belongs on the expedition board at all. Only a hero that has
## been taken over: an untaken one has nothing to show but a price, and the
## Heroes tab is where prices are paid.
var is_visible: bool:
	get: return App.is_hero_recruited(_id)

var level_text: String:
	get: return "Level %d / %d" % [App.hero_level(_id), App.hero_level_cap(_id)]

var chain_text: String:
	get: return "Chain %d / %d" % [App.chain_position(_id), App.chain_length(_id)]

var progress_ratio: float:
	get: return App.mission_progress_ratio(_entry())

var is_out: bool:
	get: return not _entry().is_empty()

var is_complete: bool:
	get: return App.is_mission_complete(_entry())

## The step this row is about: the one in flight, or the next one up.
var step_name: String:
	get:
		var def := _step_def()
		return def.display_name if def != null else "Chain walked"

## What the step pays and what it leaves behind. Read off the mission's own
## ViewModel rather than re-derived here, so the two rows cannot drift apart.
var step_reward_text: String:
	get:
		var vm := _step_vm()
		return vm.reward_text() if vm != null else ""

var step_boon_text: String:
	get:
		var vm := _step_vm()
		return vm.boon_text if vm != null else ""

## The countdown while a step is out, and what the next one would take when none
## is. Empty at the end of a chain, where there is nothing to time.
var countdown_text: String:
	get:
		var entry := _entry()
		if not entry.is_empty():
			if App.is_mission_complete(entry):
				return "Ready"
			return _duration_text(App.mission_seconds_remaining(entry))
		var vm := _step_vm()
		return vm.duration_text() if vm != null else ""

var action_text: String:
	get:
		if is_out:
			return "Collect"
		return "Send"

var can_act: bool:
	get:
		if is_out:
			return is_complete
		return not App.sendable_step(_id).is_empty()

## Why the button is dark, when it is. Empty while the hero can simply be sent,
## which is the common case and wants no sentence of its own.
var status_text: String:
	get:
		if is_out or can_act:
			return ""
		var step := _step_def()
		if step == null:
			return "Every expedition in this chain is done."
		var owed := App.levels_until_mission_unlock(step.id)
		if owed > 0:
			return "%s opens at level %d" % [step.display_name, step.min_hero_level]
		if not App.is_parasitic_control_active():
			return "The ruins are sealed."
		return ""

# --- Lifecycle ---

func _init(hero_id_value: StringName, def: HeroDef) -> void:
	_id = hero_id_value
	_def = def
	App.ruins_data.active_changed.connect(_on_changed)
	App.ruins_data.heroes_changed.connect(_on_changed)
	App.ruins_data.expeditions_changed.connect(_on_changed)
	# A boost or a perk moves what a step pays and how long it takes, and both
	# can be bought from another screen while the board is open.
	App.mission_upgrade_system.upgrades_changed.connect(_on_changed)
	App.prestige_upgrade_system.upgrades_changed.connect(_on_changed)
	App.expedition_upgrade_system.upgrades_changed.connect(_on_changed)
	# Losing the Ruins to a sporation stops the board, which every row shows.
	App.biomes_data.biome_unlocked.connect(_on_changed.unbind(1))

func dispose() -> void:
	App.ruins_data.active_changed.disconnect(_on_changed)
	App.ruins_data.heroes_changed.disconnect(_on_changed)
	App.ruins_data.expeditions_changed.disconnect(_on_changed)
	App.mission_upgrade_system.upgrades_changed.disconnect(_on_changed)
	App.prestige_upgrade_system.upgrades_changed.disconnect(_on_changed)
	App.expedition_upgrade_system.upgrades_changed.disconnect(_on_changed)
	App.biomes_data.biome_unlocked.disconnect(_on_changed.unbind(1))

## Driven by the Ruins panel's one-second timer, not by a model signal: nothing
## in the model moves as an expedition counts down. See RuinsViewModel.
func notify_clock_moved() -> void:
	_notify(PROP_CLOCK_MOVED)

# --- Model -> notification plumbing ---

func _on_changed() -> void:
	_notify(PROP_EXPEDITION_CHANGED)

# --- Reading the board ---

func _entry() -> Dictionary:
	return App.ruins_data.find_by_hero(_id)

## The step in flight, or the next one up, or null at the end of the chain.
func _step_def() -> MissionDef:
	var entry := _entry()
	if not entry.is_empty():
		return App.mission_def(entry["mission_id"])
	return App.next_chain_step(_id)

func _step_vm() -> MissionViewModel:
	var def := _step_def()
	return App.mission_vms.get(def.id) if def != null else null

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
