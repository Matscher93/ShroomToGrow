class_name RuinsViewModel
extends ViewModel
## VIEWMODEL: the Ruins screen's own state - which tab is up, where the player
## left it, and the header line over the mission board.
## Owns formatting and derived state.
## References the model, never a Node.
##
## The per-slot, per-mission, per-creature and per-boost cards bind their own VMs
## (App.mission_slot_vm(), App.mission_vms, App.creature_vms,
## App.mission_boost_vms); this one owns what is shared across the screen. The three currency balances are shown by the top
## bar, from the screen definition's currencies - this screen does not repeat
## them.

const PROP_BOARD_CHANGED := &"board_changed"
const PROP_CREATURES_VISIBLE := &"creatures_visible"
## The farms section came or went, or the boards changed width. Split from
## PROP_BOARD_CHANGED because it is the one thing that adds and removes cards
## rather than repainting them.
const PROP_BOARDS_RESIZED := &"boards_resized"
## The wall clock moved. Split from PROP_BOARD_CHANGED so the panel's poll
## rewrites its header rather than rebuilding a list under the player's finger.
const PROP_CLOCK_MOVED := &"clock_moved"
## The nav menu asked for one of this screen's tabs by name. Only needed when the
## screen is already up: arriving from another screen respawns it, and _ready()
## reads current_tab on its own.
const PROP_TAB_REQUESTED := &"tab_requested"

## Names of the tabs in child order, for the chip that says which one is up. The
## tab bar itself is hidden - the nav menu switches these - so this label is the
## only thing on screen saying where the player is.
const TAB_NAMES: Array[String] = ["Missions", "Creatures", "Boosts"]

## The stats that only ever move the Ruins themselves. A boost rung writing
## anything outside this set reaches the rest of the game, which is what the
## ladder's General half means - see MissionBoostViewModel.is_general.
##
## Lives here rather than on the card VM because it describes the ladder, not one
## rung of it, and the panel groups by the same answer.
const CONTROL_STATS: Array[StringName] = [&"mission_speed", &"farm_slots",
	&"mission_reward", &"relic_gain", &"ichor_gain", &"glyph_gain",
	&"creature_rank_cap"]

## Seconds between polls of the wall clock. This is the *header's* cadence, and
## the catch-up for cards sitting on a hidden tab - a card on screen animates its
## own bar per frame, since a poll interval is exactly what a stepping bar looks
## like. A second is as fine as the header needs: it counts whole missions.
const CLOCK_POLL_INTERVAL := 1.0

# --- View state ---
## Where the player left this screen. Parked here because App owns ViewModels for
## the app's lifetime while the screen itself is freed on every nav switch, and
## re-finding a tab and a scroll position on every visit is the single most
## expensive thing this screen asks of the player. Same reasoning as
## CrystalCavesViewModel. Not saved: view state, not progress.
var current_tab := 0
## Scroll offset per scrolling tab, keyed by tab index.
var scroll_offsets: Dictionary = {}

# --- Read-only display properties bound by the View ---

## Whether the Creatures tab belongs on screen at all. Before the first creature
## is within reach the tab is a page of locked cards and nothing the player can
## act on - one tab too many on a screen reached from a phone's thumb.
##
## Gated on is_unlocked rather than is_recruited so the tab arrives *before* the
## first recruit, which is the only place the player can make one.
var creatures_visible: bool:
	get:
		for def in App.creature_defs.creatures:
			if App.is_creature_unlocked(def.id):
				return true
		return false

## Whether the farms belong on screen at all. Before the first expedition that
## opens one is finished there is nothing to put in a plot, and an empty section
## headed FARMS is a promise the player cannot act on.
var farms_visible: bool:
	get:
		for def in App.mission_defs.missions:
			if def.is_farm and App.is_mission_unlocked(def.id):
				return true
		return not App.active_farms().is_empty()

## One card per expedition actually out. There are no empty expedition slots to
## draw: the board is uncapped, so what would fill an empty one is the Send
## button under the list rather than a place reserved for it.
var expedition_slot_vms: Array[MissionSlotViewModel]:
	get: return _slot_vms(App.expeditions_out(), false)

## One card per farm plot, filled or free - the farms are capped, so an empty
## plot is a real place and worth showing as one.
var farm_slot_vms: Array[MissionSlotViewModel]:
	get: return _slot_vms(App.farm_slots(), true)

## Whether there is an expedition to send and somebody free to send on it. What
## the Send button under the expedition list reads.
var can_send_expedition: bool:
	get:
		for vm in sendable_missions(false):
			if not vm.best_creature_id.is_empty():
				return true
		return false

## Why the Send button is dark, when it is. Says which half is missing, because
## the two want opposite things from the player: another creature taken over, or
## an expedition opened by working the ladder.
var send_expedition_hint: String:
	get:
		if can_send_expedition:
			return ""
		if sendable_missions(false).is_empty():
			return "Every expedition is out or already run."
		return "Every creature is busy."

func _slot_vms(count: int, is_farm: bool) -> Array[MissionSlotViewModel]:
	var out: Array[MissionSlotViewModel] = []
	for i in range(count):
		out.append(App.mission_slot_vm(i, is_farm))
	return out

## The missions the chooser offers for one of the two boards: unlocked, and not
## already out.
##
## A mission already in flight is dropped rather than shown disabled - one
## mission id can only be out once at a time, so offering it again is offering a
## press that refuses itself.
func sendable_missions(is_farm: bool) -> Array[MissionViewModel]:
	var out: Array[MissionViewModel] = []
	for def in App.mission_defs.missions:
		if def.is_farm != is_farm:
			continue
		if not App.is_mission_unlocked(def.id):
			continue
		if not App.active_mission(def.id).is_empty():
			continue
		out.append(App.mission_vms[def.id])
	return out

## Every expedition still ahead of the player, in ladder order, for the section
## that says what is left. Finished ones are dropped: a list of things that
## cannot be done again is not a list worth scrolling.
var remaining_expedition_vms: Array[MissionViewModel]:
	get:
		var out: Array[MissionViewModel] = []
		for def in App.mission_defs.missions:
			if def.is_farm or App.is_mission_completed(def.id):
				continue
			out.append(App.mission_vms[def.id])
		return out

var expeditions_left_text: String:
	get:
		var count := remaining_expedition_vms.size()
		if count == 0:
			return "Every expedition run"
		return "%d expedition%s left" % [count, "" if count == 1 else "s"]

var farm_board_text: String:
	get: return "%d of %d running" % [App.farm_slots_used(), App.farm_slots()]

## The line over the board. Says what the Ruins are doing rather than what they
## hold: the slot count is the number every perk in the Dominion branch moves.
var board_text: String:
	get:
		if not App.is_parasitic_control_active():
			return "The ruins are quiet. Reopen The Ruins to take control again."
		var ready := App.collectable_mission_count()
		var line := "%d out" % App.expeditions_out()
		if ready > 0:
			line += " - %d ready to collect" % ready
		return line

var missions_text: String:
	get: return "%d missions completed" % App.missions_completed()

var has_collectable: bool:
	get: return App.collectable_mission_count() > 0

var creature_vms_ordered: Array[CreatureViewModel]:
	get:
		var ordered: Array[CreatureViewModel] = []
		for def in App.creature_defs.creatures:
			ordered.append(App.creature_vms[def.id])
		return ordered

## Control rungs first, then general ones. The player arrives here to make the
## board work harder, and the rungs that reach the rest of the game only start
## mattering once it does.
var boost_vms_ordered: Array[MissionBoostViewModel]:
	get:
		var control: Array[MissionBoostViewModel] = []
		var general: Array[MissionBoostViewModel] = []
		for def in App.mission_boosts.boosts:
			var vm: MissionBoostViewModel = App.mission_boost_vms[def.id]
			if vm.is_general:
				general.append(vm)
			else:
				control.append(vm)
		return control + general

# --- View -> ViewModel ---

func collect_all() -> void:
	App.collect_all_missions()

## The chip's caption. Takes the index rather than reading current_tab because
## the two can disagree: a remembered tab that is now hidden leaves the screen
## showing a different one, and the chip has to name what is actually up.
func tab_label(index: int) -> String:
	if index < 0 or index >= TAB_NAMES.size():
		return ""
	return TAB_NAMES[index]

## Driven by the panel's one-second timer. Nothing in the model moves while a
## mission counts down - completion is derived from two timestamps - so there is
## no signal to bind and the read has to be asked for.
func poll_clock() -> void:
	for vm: MissionViewModel in App.mission_vms.values():
		vm.notify_clock_moved()
	for vm: MissionSlotViewModel in App.mission_slot_vms.values():
		vm.notify_clock_moved()
	_notify(PROP_CLOCK_MOVED)

# --- Lifecycle ---

func _init() -> void:
	App.ruins_data.active_changed.connect(_on_board_changed)
	App.ruins_data.creatures_changed.connect(_on_creatures_changed)
	App.ruins_data.missions_completed_changed.connect(_on_creatures_changed.unbind(1))
	App.ruins_data.expeditions_changed.connect(_on_boards_resized)
	# Losing or reopening the Ruins is what starts and stops the board.
	App.biomes_data.biome_unlocked.connect(_on_board_changed.unbind(1))
	# &"farm_slots" comes from both tracks, so either can widen the farm board.
	App.mission_upgrade_system.upgrades_changed.connect(_on_boards_resized)
	App.prestige_upgrade_system.upgrades_changed.connect(_on_boards_resized)
	App.screens_data.sub_screen_requested.connect(_on_sub_screen_requested)

func dispose() -> void:
	App.ruins_data.active_changed.disconnect(_on_board_changed)
	App.ruins_data.creatures_changed.disconnect(_on_creatures_changed)
	App.ruins_data.missions_completed_changed.disconnect(_on_creatures_changed.unbind(1))
	App.ruins_data.expeditions_changed.disconnect(_on_boards_resized)
	App.biomes_data.biome_unlocked.disconnect(_on_board_changed.unbind(1))
	App.mission_upgrade_system.upgrades_changed.disconnect(_on_boards_resized)
	App.prestige_upgrade_system.upgrades_changed.disconnect(_on_boards_resized)
	App.screens_data.sub_screen_requested.disconnect(_on_sub_screen_requested)

# --- Model -> notification plumbing ---

func _on_board_changed() -> void:
	_notify(PROP_BOARD_CHANGED)

## Finishing an expedition can open a farm, which brings a whole section on
## screen, and a widened board brings slot cards with it. Both add and remove
## cards rather than repainting them, so they are announced separately.
func _on_boards_resized() -> void:
	_notify(PROP_BOARDS_RESIZED)
	_notify(PROP_BOARD_CHANGED)

## The tally moves both the header and which cards are unlocked, so it notifies
## both. Collecting a mission is the one action that does.
func _on_creatures_changed() -> void:
	_notify(PROP_CREATURES_VISIBLE)
	_notify(PROP_BOARD_CHANGED)

## Every screen's sub-view requests come through the one signal, so this filters
## for its own. Setting current_tab is enough for the cold path - the screen is
## respawned and _restore_view_state() reads it - and the notify is what moves an
## already-open screen.
func _on_sub_screen_requested(screen_type: ScreenTypes.Types, sub_index: int) -> void:
	if screen_type != ScreenTypes.Types.RUINS:
		return
	current_tab = sub_index
	_notify(PROP_TAB_REQUESTED)
