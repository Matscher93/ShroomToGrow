@tool
extends PanelContainer
## VIEW: the Ruins screen. Three tabs: the two boards, the roster of controlled
## creatures, and the ladder the mission currencies buy.
##
## The Missions tab is built out of what is actually happening, not out of the
## ladder. There are dozens of missions and only a few running, so a flat list of
## the first made the player scroll past everything they could not act on to reach
## the two or three they could. What is on screen now is the expeditions that are
## out, the farms that are running, and the free plots between them - with the
## choosing moved into a sheet opened on purpose.
##
## The expeditions have no reserved places: the board is uncapped, so the list is
## exactly as long as the number out and the way to add one is the button under
## it. The farms do have places, because they are capped, so a free plot is drawn
## as the real thing it is.
##
## Under them sits the ledger of expeditions still ahead, folded shut. It is the
## thing to work towards rather than the thing to do now, which is why it is one
## row until the player asks for it.
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
@export var creatures_tab: ScrollContainer
@export var boosts_tab: ScrollContainer
@export var vbox_expeditions: VBoxContainer
@export var vbox_farms: VBoxContainer
@export var btn_send_expedition: Button
@export var lbl_send_hint: Label
@export var section_farms: VBoxContainer
@export var lbl_farm_board: Label
@export var btn_ledger: Button
@export var vbox_ledger: VBoxContainer
@export var chooser_layer: PopupLayer
@export var vbox_creatures: VBoxContainer
@export var vbox_boosts: VBoxContainer
@export var lbl_current_tab: Label
@export var lbl_board: Label
@export var lbl_missions: Label
@export var btn_collect_all: Button
@export var slot_card_scene: PackedScene
@export var choice_row_scene: PackedScene
@export var chooser_scene: PackedScene
@export var creature_card_scene: PackedScene
@export var boost_card_scene: PackedScene

var _vm: RuinsViewModel
var _countdown_timer: Timer
## Whether the ledger of remaining expeditions is folded open. Held here rather
## than on the ViewModel because it is not worth remembering across a nav switch:
## it is opened to answer one question and shut again.
var _ledger_open := false

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
	btn_ledger.pressed.connect(_on_ledger_pressed)
	btn_send_expedition.pressed.connect(_on_send_expedition_pressed)
	bind(App.ruins_vm)
	_build_boards()
	_build_ledger()
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
			# The expedition list is exactly as long as the number out, so
			# sending or collecting one changes how many cards there are.
			# Structural, so it waits for the finger.
			_guard.run_when_free(&"expeditions", _rebuild_expeditions)
		RuinsViewModel.PROP_BOARDS_RESIZED:
			# The farm board only changes width, which is rarer and worth not
			# freeing a running farm's card for on every send.
			_guard.run_when_free(&"boards", _rebuild_boards)
		RuinsViewModel.PROP_CREATURES_VISIBLE:
			_guard.run_when_free(&"creatures_tab", _refresh_creatures_tab)
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
	btn_ledger.text = "%s %s" % ["\u25be" if _ledger_open else "\u25b8", _vm.expeditions_left_text]
	vbox_ledger.visible = _ledger_open
	btn_send_expedition.disabled = not _vm.can_send_expedition
	lbl_send_hint.text = _vm.send_expedition_hint
	lbl_send_hint.visible = not lbl_send_hint.text.is_empty()

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

## An empty slot was tapped. The chooser lives in this screen's own PopupLayer
## rather than the main screen's overlay layer: it belongs to the board, it goes
## away when the player leaves the board, and the layer's static count is what
## keeps the touch scrollers underneath from scrolling behind it.
func _on_fill_requested(is_farm: bool) -> void:
	var chooser := chooser_layer.show_popup(chooser_scene)
	chooser.set_board(is_farm)
	chooser.dismissed.connect(chooser_layer.clear, CONNECT_ONE_SHOT)

## The way to start an expedition, now that there is no empty slot to tap. Opens
## the same chooser an empty farm plot does.
func _on_send_expedition_pressed() -> void:
	_on_fill_requested(false)

func _on_ledger_pressed() -> void:
	_ledger_open = not _ledger_open
	_refresh_header()

# --- Building ---

## Both boards, one slot card per place. Rebuilt only when a board changes width,
## which is the only thing that changes how many cards there are - what is *in* a
## place is a repaint the card handles itself.
func _build_boards() -> void:
	_build_slots(vbox_expeditions, _vm.expedition_slot_vms)
	_build_slots(vbox_farms, _vm.farm_slot_vms)

func _build_slots(container: VBoxContainer, vms: Array[MissionSlotViewModel]) -> void:
	_clear(container)
	for vm in vms:
		var card := slot_card_scene.instantiate()
		container.add_child(card)
		card.bind(vm)
		card.fill_requested.connect(_on_fill_requested)

## A widened farm board brings a plot with it, and a finished expedition drops a
## row out of the ledger. Both are structural, so both come through here.
func _rebuild_boards() -> void:
	_build_boards()
	_build_ledger()
	_refresh_header()

## Just the expedition list, which changes length on every send and every
## collect - far more often than the farm board changes width.
func _rebuild_expeditions() -> void:
	_build_slots(vbox_expeditions, _vm.expedition_slot_vms)
	_refresh_header()

## What is still ahead, in ladder order. Rows are read-only here: the ledger says
## what is coming, and starting one is the chooser's job.
func _build_ledger() -> void:
	_clear(vbox_ledger)
	for vm in _vm.remaining_expedition_vms:
		var row := choice_row_scene.instantiate()
		vbox_ledger.add_child(row)
		row.bind(vm, false)

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
