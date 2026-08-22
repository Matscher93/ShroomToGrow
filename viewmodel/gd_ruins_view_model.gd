class_name RuinsViewModel
extends ViewModel
## VIEWMODEL: the Ruins screen's own state - which tab is up, where the player
## left it, and the header line over the mission board.
## Owns formatting and derived state.
## References the model, never a Node.
##
## The per-mission, per-creature and per-boost cards bind their own VMs
## (App.mission_vms, App.creature_vms, App.mission_boost_vms); this one owns what
## is shared across the screen. The three currency balances are shown by the top
## bar, from the screen definition's currencies - this screen does not repeat
## them.

const PROP_BOARD_CHANGED := &"board_changed"
const PROP_CREATURES_VISIBLE := &"creatures_visible"
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
const CONTROL_STATS: Array[StringName] = [&"mission_speed", &"mission_slots",
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

## The line over the board. Says what the Ruins are doing rather than what they
## hold: the slot count is the number every perk in the Dominion branch moves.
var board_text: String:
	get:
		if not App.is_parasitic_control_active():
			return "The ruins are quiet. Reopen The Ruins to take control again."
		var ready := App.collectable_mission_count()
		var line := "%d of %d creatures out" % [App.mission_slots_used(), App.mission_slots()]
		if ready > 0:
			line += " - %d ready to collect" % ready
		return line

var missions_text: String:
	get: return "%d missions completed" % App.missions_completed()

var has_collectable: bool:
	get: return App.collectable_mission_count() > 0

var mission_vms_ordered: Array[MissionViewModel]:
	get:
		var ordered: Array[MissionViewModel] = []
		for def in App.mission_defs.missions:
			ordered.append(App.mission_vms[def.id])
		return ordered

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
	_notify(PROP_CLOCK_MOVED)

# --- Lifecycle ---

func _init() -> void:
	App.ruins_data.active_changed.connect(_on_board_changed)
	App.ruins_data.creatures_changed.connect(_on_creatures_changed)
	App.ruins_data.missions_completed_changed.connect(_on_creatures_changed.unbind(1))
	# Losing or reopening the Ruins is what starts and stops the board.
	App.biomes_data.biome_unlocked.connect(_on_board_changed.unbind(1))
	# &"mission_slots" comes from both tracks, so either can widen the board.
	App.mission_upgrade_system.upgrades_changed.connect(_on_board_changed)
	App.prestige_upgrade_system.upgrades_changed.connect(_on_board_changed)
	App.screens_data.sub_screen_requested.connect(_on_sub_screen_requested)

func dispose() -> void:
	App.ruins_data.active_changed.disconnect(_on_board_changed)
	App.ruins_data.creatures_changed.disconnect(_on_creatures_changed)
	App.ruins_data.missions_completed_changed.disconnect(_on_creatures_changed.unbind(1))
	App.biomes_data.biome_unlocked.disconnect(_on_board_changed.unbind(1))
	App.mission_upgrade_system.upgrades_changed.disconnect(_on_board_changed)
	App.prestige_upgrade_system.upgrades_changed.disconnect(_on_board_changed)
	App.screens_data.sub_screen_requested.disconnect(_on_sub_screen_requested)

# --- Model -> notification plumbing ---

func _on_board_changed() -> void:
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
