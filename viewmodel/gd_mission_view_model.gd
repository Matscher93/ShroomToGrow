class_name MissionViewModel
extends ViewModel
## VIEWMODEL: one mission as the chooser offers it - what it pays, what it would
## take, and who is best placed to go.
## Owns formatting, derived state and enabled/disabled logic.
## References the model, never a Node.
##
## One per authored mission, built once and owned by App: every row repaints
## when the board moves, so they all need live state at the same time.
##
## Serves both kinds. An expedition is sent and collected once ever; a farm is
## started and stopped and pays itself. is_farm says which, and the two commands
## below are the only place the difference reaches the view.

## The board moved - a mission was sent, collected, or a gate opened.
const PROP_MISSION_CHANGED := &"mission_changed"
## The wall clock moved, and nothing in the model fired to say so. Split from the
## above because the Ruins panel polls this once a second off its own timer, and
## rebuilding a card that often would fight the player's finger.
##
## A card on screen does not need it: MissionCard drives its own bar and label
## from _process, because a wall-clock countdown is continuous and any poll
## interval shows up as the bar stepping. What this is for is the card that was
## on a hidden tab while its mission landed.
const PROP_CLOCK_MOVED := &"clock_moved"

var _id: StringName
var _def: MissionDef

# --- View -> ViewModel ---

## Puts the picked creature on this mission - sent out on an expedition, or set
## going on a farm. Returns false when it was refused, which the row treats as
## "nothing changed": can_start already says why, and a disabled button is the
## normal path.
##
## One command rather than two so the chooser does not have to branch: which of
## the two boards this lands on is a property of the mission, not of the press.
func start(creature_id: StringName) -> bool:
	if _def.is_farm:
		return App.start_farm(_id, creature_id) > 0
	return App.send_mission(_id, creature_id) > 0

func collect() -> bool:
	var entry := App.active_mission(_id)
	if entry.is_empty():
		return false
	return App.collect_mission(int(entry["instance_id"]))

# --- Read-only display properties bound by the View ---

var display_name: String:
	get: return _def.display_name

var description: String:
	get: return _def.description

var is_farm: bool:
	get: return _def.is_farm

## True once this expedition has been brought home. It never opens again, and the
## reward it granted stays granted.
var is_completed: bool:
	get: return App.is_mission_completed(_id)

var is_active: bool:
	get: return not App.active_mission(_id).is_empty()

var is_complete: bool:
	get: return App.is_mission_complete(App.active_mission(_id))

## False while the board has not been worked enough, or the gating perk is
## unbought. The card stays visible: a hidden one gives the player nothing to
## work towards.
var is_unlocked: bool:
	get: return App.is_mission_unlocked(_id)

var progress_ratio: float:
	get:
		var entry := App.active_mission(_id)
		if _def.is_farm:
			return App.farm_progress_ratio(entry)
		return App.mission_progress_ratio(entry)

## The free creature best placed to take this, or &"" when none can. What the
## chooser pre-selects, so the common path is one tap.
var best_creature_id: StringName:
	get: return App.best_creature_for_mission(_id)

## The permanent upgrade finishing this expedition grants, as a phrase. Empty for
## a farm, which grants none - it pays its payouts and nothing else.
##
## This is the reason to pick one expedition over another, so it belongs on the
## row itself rather than behind a tap.
var boon_text: String:
	get: return EffectLabel.of_effects(_def.rewards)

## The creature currently carrying this, or "" when none is.
var active_creature_id: StringName:
	get:
		var entry := App.active_mission(_id)
		return entry["creature_id"] if not entry.is_empty() else &""

var status_text: String:
	get:
		if is_completed:
			return "Done"
		if not is_unlocked:
			return _locked_text
		var entry := App.active_mission(_id)
		if entry.is_empty():
			if _def.is_farm:
				return "Rank %d or better - %s a cycle" % [_def.min_creature_rank,
					_base_duration_text]
			return "Rank %d or better - %s" % [_def.min_creature_rank, _base_duration_text]
		var creature := App.creature_def(entry["creature_id"])
		var who := creature.display_name if creature != null else "Something"
		if _def.is_farm:
			return "%s is working it" % who
		if is_complete:
			return "%s is back" % who
		return "%s is out" % who

## Why this is shut, in the order the player can act on it: a gate they can open
## by finishing something named beats one that only counts.
var _locked_text: String:
	get:
		if not _def.requires_mission_id.is_empty() \
				and not App.is_mission_completed(_def.requires_mission_id):
			return "Opens after %s" % _mission_name(_def.requires_mission_id)
		if not _def.unlock_perk_id.is_empty() \
				and App.prestige_upgrade_system.level(_def.unlock_perk_id) <= 0:
			return "Needs %s" % _perk_name(_def.unlock_perk_id)
		return "Opens after %d more missions" % App.missions_until_mission_unlock(_id)

## The countdown. Empty when nothing is out, so the row's timer line collapses
## rather than showing a stale zero.
##
## A farm never reads "Ready": it has no finish to wait for, so what is shown is
## how long the cycle in progress has left.
var countdown_text: String:
	get:
		var entry := App.active_mission(_id)
		if entry.is_empty():
			return ""
		if _def.is_farm:
			return _duration_text(App.mission_seconds_remaining(entry))
		if App.is_mission_complete(entry):
			return "Ready"
		return _duration_text(App.mission_seconds_remaining(entry))

## What this mission would pay if sent right now with `creature_id`, or with
## whoever is best placed when none is picked. While a mission is out it reports
## the snapshot instead - the row promised that number, so it is the number it
## keeps showing.
##
## On a farm this is one cycle's worth, which is what the row pairs with the
## cycle length beside it.
func reward_text(creature_id: StringName = &"") -> String:
	var entry := App.active_mission(_id)
	var who := creature_id if not creature_id.is_empty() else best_creature_id
	var payouts: Array[Dictionary] = entry["payouts"] if not entry.is_empty() \
		else App.mission_payouts(_id, who)
	var parts: PackedStringArray = []
	for payout in payouts:
		var amount := BigNumber.new(float(payout["m"]), int(payout["e"]))
		parts.append("%s %s" % [amount.to_display(), CurrencyTypes.display_name_for(int(payout["currency"]) as CurrencyTypes.Types)])
	return ", ".join(parts)

## What sending this creature would take, for the row's line under the picker.
## Falls back to whoever is best placed, so an untouched row still quotes a real
## number rather than the authored one nobody will run it at.
func duration_text(creature_id: StringName = &"") -> String:
	var who := creature_id if not creature_id.is_empty() else best_creature_id
	return _duration_text(App.mission_duration(_id, who))

## Whether this creature could be put on this mission right now, on whichever of
## the two boards it belongs to.
func can_start(creature_id: StringName) -> bool:
	if _def.is_farm:
		return App.can_start_farm(_id, creature_id)
	return App.can_send_mission(_id, creature_id)

## Creatures that could take this right now, for the card's picker. Empty is the
## normal early state, not an error: nothing has been taken over yet.
func available_creatures() -> Array[CreatureDef]:
	return App.creatures_available_for(_def)

func has_affinity(creature_id: StringName) -> bool:
	return App.creature_has_affinity(creature_id, _id)

# --- Lifecycle ---

func _init(mission_id: StringName, def: MissionDef) -> void:
	_id = mission_id
	_def = def
	App.ruins_data.active_changed.connect(_on_changed)
	App.ruins_data.creatures_changed.connect(_on_changed)
	App.ruins_data.missions_completed_changed.connect(_on_changed.unbind(1))
	# Finishing an expedition closes it and opens the farms that wait on it, and
	# neither shows up in the signals above.
	App.ruins_data.expeditions_changed.connect(_on_changed)
	# A boost or a perk moves what this pays and how long it takes, and both can
	# be bought from another screen while the board is open.
	App.mission_upgrade_system.upgrades_changed.connect(_on_changed)
	App.prestige_upgrade_system.upgrades_changed.connect(_on_changed)
	App.biome_upgrade_system.upgrades_changed.connect(_on_changed)
	# Losing the Ruins to a sporation stops the board, which every card shows.
	App.biomes_data.biome_unlocked.connect(_on_changed.unbind(1))

func dispose() -> void:
	App.ruins_data.active_changed.disconnect(_on_changed)
	App.ruins_data.creatures_changed.disconnect(_on_changed)
	App.ruins_data.missions_completed_changed.disconnect(_on_changed.unbind(1))
	App.ruins_data.expeditions_changed.disconnect(_on_changed)
	App.mission_upgrade_system.upgrades_changed.disconnect(_on_changed)
	App.prestige_upgrade_system.upgrades_changed.disconnect(_on_changed)
	App.biome_upgrade_system.upgrades_changed.disconnect(_on_changed)
	App.biomes_data.biome_unlocked.disconnect(_on_changed.unbind(1))

## Driven by the Ruins panel's own one-second timer, not by a model signal:
## nothing in the model moves as a mission counts down. See RuinsViewModel.
func notify_clock_moved() -> void:
	_notify(PROP_CLOCK_MOVED)

# --- Model -> notification plumbing ---

func _on_changed() -> void:
	_notify(PROP_MISSION_CHANGED)

# --- Formatting ---

var _base_duration_text: String:
	get: return _duration_text(_def.base_duration_seconds)

## Coarse on purpose above a minute: a mission counted to the second reads as a
## thing to sit and watch, which is the opposite of what the board is for.
func _duration_text(seconds: float) -> String:
	var total := int(ceil(maxf(0.0, seconds)))
	if total < 60:
		return "%ds" % total
	if total < 3600:
		@warning_ignore("integer_division")
		return "%dm %02ds" % [total / 60, total % 60]
	@warning_ignore("integer_division")
	return "%dh %02dm" % [total / 3600, (total % 3600) / 60]

func _mission_name(mission_id: StringName) -> String:
	var def := App.mission_def(mission_id)
	return def.display_name if def != null else "an earlier expedition"

func _perk_name(perk_id: StringName) -> String:
	var def := App.perk_def(perk_id)
	return def.display_name if def != null else "a prestige perk"
