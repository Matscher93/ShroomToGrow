@tool
extends PanelContainer
## VIEW: the Ruins screen. Three tabs: the mission board, the roster of
## controlled creatures, and the ladder the mission currencies buy.
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
## The mission cards do not ride on it. A bar redrawn on a poll steps at exactly
## that interval, so each card animates its own from _process - see MissionCard.

@export var tab_container: FullWidthTabContainer
@export var missions_tab: ScrollContainer
@export var creatures_tab: ScrollContainer
@export var boosts_tab: ScrollContainer
@export var vbox_missions: VBoxContainer
@export var vbox_creatures: VBoxContainer
@export var vbox_boosts: VBoxContainer
@export var lbl_current_tab: Label
@export var lbl_board: Label
@export var lbl_missions: Label
@export var btn_collect_all: Button
@export var mission_card_scene: PackedScene
@export var creature_card_scene: PackedScene
@export var boost_card_scene: PackedScene

var _vm: RuinsViewModel
var _countdown_timer: Timer

func _ready() -> void:
	# Autoloads aren't instantiated for @tool scripts in the editor, so the
	# ViewModels only exist at runtime.
	if Engine.is_editor_hint():
		return

	btn_collect_all.pressed.connect(_on_collect_all_pressed)
	bind(App.ruins_vm)
	_build_missions()
	_build_creatures()
	_build_boosts()
	_refresh_creatures_tab()
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
			_refresh_header()
		RuinsViewModel.PROP_CREATURES_VISIBLE:
			_refresh_creatures_tab()
		RuinsViewModel.PROP_CLOCK_MOVED:
			# The header carries the "ready to collect" count, which moves with the
			# wall clock and with nothing else.
			_refresh_header()
		RuinsViewModel.PROP_TAB_REQUESTED:
			_apply_requested_tab()

func _refresh_header() -> void:
	lbl_board.text = _vm.board_text
	lbl_missions.text = _vm.missions_text
	btn_collect_all.visible = _vm.has_collectable

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
func _refresh_creatures_tab() -> void:
	var index := creatures_tab.get_index()
	tab_container.set_tab_hidden(index, not _vm.creatures_visible)
	_refresh_tab_chip()
	# One fewer tab to share the bar, so what is left has to be repadded.
	tab_container.spread_tabs()
	if _vm.creatures_visible or tab_container.current_tab != index:
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
	return [missions_tab, creatures_tab, boosts_tab]

func _on_tab_changed(tab: int) -> void:
	_vm.current_tab = tab
	_refresh_tab_chip()

func _on_scrolled(value: float, tab: ScrollContainer) -> void:
	_vm.scroll_offsets[tab.get_index()] = int(value)

# --- View -> VM ---

func _on_collect_all_pressed() -> void:
	_vm.collect_all()

# --- Building ---

func _build_missions() -> void:
	_clear(vbox_missions)
	for vm in _vm.mission_vms_ordered:
		var card := mission_card_scene.instantiate()
		vbox_missions.add_child(card)
		card.bind(vm)

func _build_creatures() -> void:
	_clear(vbox_creatures)
	for vm in _vm.creature_vms_ordered:
		var card := creature_card_scene.instantiate()
		vbox_creatures.add_child(card)
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
