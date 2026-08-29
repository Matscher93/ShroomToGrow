class_name RuinsViewModel
extends ViewModel
## VIEWMODEL: the Ruins screen's own state - which tab is up, where the player
## left it, and the header line over the mission board.
## Owns formatting and derived state.
## References the model, never a Node.
##
## The per-slot, per-mission, per-hero and per-boost cards bind their own VMs
## (App.mission_slot_vm(), App.mission_vms, App.hero_vms,
## App.mission_boost_vms); this one owns what is shared across the screen. The three currency balances are shown by the top
## bar, from the screen definition's currencies - this screen does not repeat
## them.

const PROP_BOARD_CHANGED := &"board_changed"
const PROP_HEROES_VISIBLE := &"heroes_visible"
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
const TAB_NAMES: Array[String] = ["Missions", "Heroes", "Boosts"]

## The stats that only ever move the Ruins themselves. A boost rung writing
## anything outside this set reaches the rest of the game, which is what the
## ladder's General half means - see MissionBoostViewModel.is_general.
##
## Lives here rather than on the card VM because it describes the ladder, not one
## rung of it, and the panel groups by the same answer.
const CONTROL_STATS: Array[StringName] = [&"mission_speed", &"farm_slots",
	&"mission_reward", &"relic_gain", &"ichor_gain", &"glyph_gain",
	&"hero_level_cap"]

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

## Whether the Heroes tab belongs on screen at all. Before the first hero
## is within reach the tab is a page of locked cards and nothing the player can
## act on - one tab too many on a screen reached from a phone's thumb.
##
## Gated on is_unlocked rather than is_recruited so the tab arrives *before* the
## first recruit, which is the only place the player can make one.
var heroes_visible: bool:
	get:
		for def in App.hero_defs.heroes:
			if App.is_hero_unlocked(def.id):
				return true
		return false

## Whether the farms belong on screen at all. Before the first expedition that
## opens one is finished there is nothing to work, and a section headed FARMS is
## a promise the player cannot act on.
var farms_visible: bool:
	get: return not farm_vms.is_empty()

## One row per hero taken over. The expedition board is built out of heroes now,
## not out of places: a hero walks one chain in order, so there is exactly one
## thing each could be doing, and the row can both show it and start it.
var hero_expedition_vms: Array[HeroExpeditionViewModel]:
	get:
		var out: Array[HeroExpeditionViewModel] = []
		for def in App.hero_defs.heroes:
			var vm: HeroExpeditionViewModel = App.hero_expedition_vms[def.id]
			if vm.is_visible:
				out.append(vm)
		return out

## One row per farm the player has opened, running or not. A farm at zero workers
## is a farm nobody is on rather than a plot standing empty, so there is nothing
## to pick and nowhere to pick it.
var farm_vms: Array[FarmViewModel]:
	get:
		var out: Array[FarmViewModel] = []
		for def in App.mission_defs.missions:
			if not def.is_farm:
				continue
			var vm: FarmViewModel = App.farm_vms[def.id]
			if vm.is_visible:
				out.append(vm)
		return out

## Why the expedition board is empty, when it is. Shown in place of the rows, so
## it says the one thing that would fill them.
var expeditions_hint: String:
	get:
		if not hero_expedition_vms.is_empty():
			return ""
		return "Take a hero over to start walking a chain."

## Where every hero stands in its own chain, for the line over the board.
var chain_progress_text: String:
	get:
		var parts: PackedStringArray = []
		for vm in hero_expedition_vms:
			parts.append("%s %d/%d" % [vm.display_name,
				App.chain_position(vm.hero_id), App.chain_length(vm.hero_id)])
		return " · ".join(parts)

## The worker pool line: how many are free of how many were ever hired.
var worker_pool_text: String:
	get: return "%d idle / %d hired" % [App.workers_idle(), App.workers_owned()]

## The price of the next worker, spelled out in every currency it costs.
var worker_price_text: String:
	get:
		var parts: PackedStringArray = []
		for price: Dictionary in App.worker_prices():
			var amount: BigNumber = price["amount"]
			parts.append("%s %s" % [amount.to_display(), String(price["field"])])
		return " · ".join(parts)

var can_hire_worker: bool:
	get: return App.can_hire_worker()

## Whether the workers belong on screen at all. Nothing can be done with one
## before there is a farm to put it on.
var workers_visible: bool:
	get: return farms_visible

func hire_worker() -> void:
	App.hire_worker()

var farm_board_text: String:
	get: return "%d of %d running" % [App.farm_slots_used(), App.farm_slots()]

## The line over the board. Says what the Ruins are doing rather than what they
## hold: the slot count is the number every perk in the Dominion branch moves.
var board_text: String:
	get:
		if not App.is_parasitic_control_active():
			return "The ruins are quiet. Reopen The Ruins to take control again."
		var ready := App.collectable_mission_count()
		var line := "%d of %d heroes out" % [App.expeditions_out(), hero_expedition_vms.size()]
		if ready > 0:
			line += " - %d ready to collect" % ready
		return line

var missions_text: String:
	get: return "%d missions completed" % App.missions_completed()

var has_collectable: bool:
	get: return App.collectable_mission_count() > 0

var hero_vms_ordered: Array[HeroViewModel]:
	get:
		var ordered: Array[HeroViewModel] = []
		for def in App.hero_defs.heroes:
			ordered.append(App.hero_vms[def.id])
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
	for vm: HeroExpeditionViewModel in App.hero_expedition_vms.values():
		vm.notify_clock_moved()
	for vm: FarmViewModel in App.farm_vms.values():
		vm.notify_clock_moved()
	_notify(PROP_CLOCK_MOVED)

# --- Lifecycle ---

func _init() -> void:
	App.ruins_data.active_changed.connect(_on_board_changed)
	App.ruins_data.heroes_changed.connect(_on_heroes_changed)
	App.ruins_data.missions_completed_changed.connect(_on_heroes_changed.unbind(1))
	App.ruins_data.expeditions_changed.connect(_on_boards_resized)
	App.ruins_data.workers_changed.connect(_on_board_changed)
	# Losing or reopening the Ruins is what starts and stops the board.
	App.biomes_data.biome_unlocked.connect(_on_board_changed.unbind(1))
	# &"farm_slots" comes from both tracks, so either can widen the farm board.
	App.mission_upgrade_system.upgrades_changed.connect(_on_boards_resized)
	App.prestige_upgrade_system.upgrades_changed.connect(_on_boards_resized)
	App.screens_data.sub_screen_requested.connect(_on_sub_screen_requested)

func dispose() -> void:
	App.ruins_data.active_changed.disconnect(_on_board_changed)
	App.ruins_data.heroes_changed.disconnect(_on_heroes_changed)
	App.ruins_data.missions_completed_changed.disconnect(_on_heroes_changed.unbind(1))
	App.ruins_data.expeditions_changed.disconnect(_on_boards_resized)
	App.ruins_data.workers_changed.disconnect(_on_board_changed)
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
## Taking a hero over adds a row to the expedition board, and levelling one can
## open the step in front of it - so a roster change is structural here, not just
## a repaint.
func _on_heroes_changed() -> void:
	_notify(PROP_HEROES_VISIBLE)
	_notify(PROP_BOARDS_RESIZED)
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
