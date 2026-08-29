@tool
extends PanelContainer
## VIEW: the Ruins screen. Three tabs: the two boards, the roster of controlled
## heroes, and the ladder the mission currencies buy.
##
## The Missions tab is one row per thing the player owns: one per hero taken over,
## and one per farm opened. Nothing is chosen and there is nowhere to choose it.
##
## That is the whole shape of it. A hero walks exactly one chain in order, so the
## step it could run next is not a choice - the row shows it and the button starts
## it. A farm is worked by however many workers are put on it, so the stepper on
## its row is the whole interface: from zero it starts the farm, and stepping the
## last worker off stops it. Both used to be sheets the player opened on purpose,
## and neither was ever offering more than one answer.
##
## The tab bar is hidden for the same reason the Crystal Caves' is - the nav menu
## lists these three as sub-rows under Ruins, and a second row of tabs at the
## bottom was competing with the menu disc for the same thumb. The chip above the
## TabContainer says which tab is up.
##
## The three currency balances are not repeated here. The screen definition lists
## them, so the top bar already shows all three labelled above every tab.
##
## This screen owns one thing no other screen does: a clock poll. Missions finish
## on the wall clock, so nothing in the model moves as one counts down and there
## is no signal to bind. The timer below asks the ViewModel to re-read it once a
## second, which is what keeps the header honest and catches up any card that was
## on a hidden tab while its mission landed. It runs only while the screen is up,
## which is the whole reason it lives on the view.
##
## The slot cards do not ride on it. A bar redrawn on a poll steps at exactly that
## interval, so each card animates its own from _process - see SlotCard.

@export var tab_container: FullWidthTabContainer
@export var missions_tab: ScrollContainer
@export var heroes_tab: ScrollContainer
@export var boosts_tab: ScrollContainer
@export var vbox_expeditions: VBoxContainer
@export var vbox_farms: VBoxContainer
@export var lbl_expeditions_hint: Label
@export var section_workers: VBoxContainer
@export var lbl_worker_pool: Label
@export var btn_hire_worker: Button
@export var section_farms: VBoxContainer
@export var lbl_farm_board: Label
@export var vbox_heroes: VBoxContainer
@export var vbox_boosts: VBoxContainer
@export var lbl_current_tab: Label
@export var lbl_board: Label
@export var lbl_missions: Label
@export var btn_collect_all: Button
@export var hero_expedition_card_scene: PackedScene
@export var farm_card_scene: PackedScene
@export var hero_card_scene: PackedScene
@export var boost_card_scene: PackedScene

var _vm: RuinsViewModel
var _countdown_timer: Timer

## Holds structural refreshes back while the player has the pointer down, so a
## tick landing mid-press cannot free or reflow the button under their finger.
var _guard := PressGuard.new()

func _ready() -> void:
	# Parented before the editor-hint bail below: an unparented guard is an orphan
	# Node this panel would leak on every rebuild.
	add_child(_guard)
	# Autoloads aren't instantiated for @tool scripts in the editor, so the
	# ViewModels only exist at runtime.
	if Engine.is_editor_hint():
		return

	btn_collect_all.pressed.connect(_on_collect_all_pressed)
	btn_hire_worker.pressed.connect(_on_hire_worker_pressed)
	bind(App.ruins_vm)
	_build_boards()
	_build_heroes()
	_build_boosts()
	_refresh_heroes_tab()
	_start_countdown()
	await _restore_view_state()

func bind(vm: RuinsViewModel) -> void:
	if _vm:
		_vm.property_changed.disconnect(_on_property_changed)
	_vm = vm
	_vm.property_changed.connect(_on_property_changed)
	_refresh_header()

func _exit_tree() -> void:
	if _vm:
		_vm.property_changed.disconnect(_on_property_changed)
		_vm = null

func _on_property_changed(property: StringName) -> void:
	match property:
		RuinsViewModel.PROP_BOARD_CHANGED:
			# The rows repaint themselves off their own ViewModels, so a send or
			# a collect needs nothing structural here - only the header.
			_refresh_header()
		RuinsViewModel.PROP_BOARDS_RESIZED:
			# A recruit, a finished expedition or a widened board all change how
			# many rows there are. Structural, so it waits for the finger.
			#
			# Deferred as well as guarded: collecting arrives from inside a row's
			# own `pressed` handler, and rebuilding there frees the card that
			# handler is still running in - which then repaints itself off a
			# ViewModel its own _exit_tree() has already dropped. This is the
			# case PressGuard's `defer` exists for.
			_guard.run_when_free(&"boards", _rebuild_boards, true)
		RuinsViewModel.PROP_HEROES_VISIBLE:
			_guard.run_when_free(&"heroes_tab", _refresh_heroes_tab)
		RuinsViewModel.PROP_CLOCK_MOVED:
			# The header carries the "ready to collect" count, which moves with the
			# wall clock and with nothing else.
			_refresh_header()
		RuinsViewModel.PROP_TAB_REQUESTED:
			_apply_requested_tab()

func _refresh_header() -> void:
	lbl_board.text = _vm.board_text
	lbl_missions.text = _vm.missions_text
	lbl_farm_board.text = _vm.farm_board_text
	btn_collect_all.visible = _vm.has_collectable
	section_farms.visible = _vm.farms_visible
	# The workers arrive with the farms: there is nothing to put one on before
	# the first farm opens, so hiring one would be money into a hole.
	section_workers.visible = _vm.workers_visible
	lbl_worker_pool.text = _vm.worker_pool_text
	btn_hire_worker.text = "Hire a worker   %s" % _vm.worker_price_text
	btn_hire_worker.disabled = not _vm.can_hire_worker
	lbl_expeditions_hint.text = _vm.expeditions_hint
	lbl_expeditions_hint.visible = not lbl_expeditions_hint.text.is_empty()

# --- The clock poll ---

func _start_countdown() -> void:
	_countdown_timer = Timer.new()
	_countdown_timer.wait_time = RuinsViewModel.CLOCK_POLL_INTERVAL
	_countdown_timer.timeout.connect(_on_countdown_tick)
	add_child(_countdown_timer)
	_countdown_timer.start()

func _on_countdown_tick() -> void:
	if _vm == null:
		return
	_vm.poll_clock()

# --- Tabs ---

## Missions leads the tabs, so it is also the one the screen opens on. Hiding the
## current tab leaves TabContainer pointing at a tab that is no longer there, so
## the selection is moved to the first one still showing.
func _refresh_heroes_tab() -> void:
	var index := heroes_tab.get_index()
	tab_container.set_tab_hidden(index, not _vm.heroes_visible)
	_refresh_tab_chip()
	# One fewer tab to share the bar, so what is left has to be repadded.
	tab_container.spread_tabs()
	if _vm.heroes_visible or tab_container.current_tab != index:
		return
	for i in range(tab_container.get_tab_count()):
		if not tab_container.is_tab_hidden(i):
			tab_container.current_tab = i
			return

## The nav menu asked for one of these tabs while the screen was already up.
## Arriving from another screen respawns the screen instead, and _ready() reads
## the same remembered tab on its own.
##
## A hidden tab is ignored rather than forced: the menu does not offer a row for
## one, so a request for it is stale state, not a destination.
func _apply_requested_tab() -> void:
	if tab_container.is_tab_hidden(_vm.current_tab):
		return
	tab_container.current_tab = _vm.current_tab
	_refresh_tab_chip()

func _refresh_tab_chip() -> void:
	lbl_current_tab.text = _vm.tab_label(tab_container.current_tab)

# --- View state ---

## Puts the screen back where the player left it. Screens are freed on every nav
## switch (see GameScreens), so without this a glance at another screen costs the
## player their tab and their place in the list.
##
## Scroll is restored a frame late on purpose: a ScrollContainer has no content
## height until it has been laid out once, and setting an offset before then is
## clamped to zero.
func _restore_view_state() -> void:
	if not tab_container.is_tab_hidden(_vm.current_tab):
		tab_container.current_tab = _vm.current_tab
	tab_container.tab_changed.connect(_on_tab_changed)
	_refresh_tab_chip()
	for tab in _scrolling_tabs():
		tab.get_v_scroll_bar().value_changed.connect(_on_scrolled.bind(tab))
	await get_tree().process_frame
	# The player can leave the screen inside that frame, which frees this node.
	if not is_inside_tree() or _vm == null:
		return
	for tab in _scrolling_tabs():
		tab.scroll_vertical = int(_vm.scroll_offsets.get(tab.get_index(), 0))

func _scrolling_tabs() -> Array[ScrollContainer]:
	return [missions_tab, heroes_tab, boosts_tab]

func _on_tab_changed(tab: int) -> void:
	_vm.current_tab = tab
	_refresh_tab_chip()

func _on_scrolled(value: float, tab: ScrollContainer) -> void:
	_vm.scroll_offsets[tab.get_index()] = int(value)

# --- View -> VM ---

func _on_collect_all_pressed() -> void:
	_vm.collect_all()

func _on_hire_worker_pressed() -> void:
	_vm.hire_worker()

# --- Building ---

## Both boards: one row per hero taken over, one per farm opened. Rebuilt when
## either list changes length, which is what a recruit, a finished expedition or
## a widened board all do.
func _build_boards() -> void:
	_clear(vbox_expeditions)
	for vm in _vm.hero_expedition_vms:
		var card := hero_expedition_card_scene.instantiate()
		vbox_expeditions.add_child(card)
		card.bind(vm)
	_clear(vbox_farms)
	for vm in _vm.farm_vms:
		var card := farm_card_scene.instantiate()
		vbox_farms.add_child(card)
		card.bind(vm)

func _rebuild_boards() -> void:
	_build_boards()
	_refresh_header()

func _build_heroes() -> void:
	_clear(vbox_heroes)
	for vm in _vm.hero_vms_ordered:
		var card := hero_card_scene.instantiate()
		vbox_heroes.add_child(card)
		card.bind(vm)

func _build_boosts() -> void:
	_clear(vbox_boosts)
	for vm in _vm.boost_vms_ordered:
		var card := boost_card_scene.instantiate()
		vbox_boosts.add_child(card)
		card.bind(vm)

func _clear(container: Container) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()
