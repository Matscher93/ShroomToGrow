extends PanelContainer
## VIEW: the statistics sheet, shown as a full-screen overlay over whatever screen
## the player is on. Opened from the top bar and built exactly like the
## achievement archive next to it: the root is the dimmed backdrop and tapping it
## closes, the sheet inside swallows its own presses.
##
## Four tabs over one content box rather than four scrolling lists side by side.
## Three of them are cheap, and the fourth - the bonus breakdown - walks every
## levelled upgrade in all eight tracks, so it is built when it is opened and not
## before. See StatisticsViewModel.refresh_bonuses().

## Emitted when the player dismisses the overlay. Whoever spawned this instance
## owns freeing it. This view never queue_frees itself, so it can't desync the
## PopupLayer's tracked ref.
signal dismissed

enum Tab { RECORDS, TIMELINE, RUNS, BONUSES }

@export var btn_close: Button
@export var btn_records: Button
@export var btn_timeline: Button
@export var btn_runs: Button
@export var btn_bonuses: Button
@export var lbl_empty: Label
@export var scroll: ScrollContainer
@export var vbox_content: VBoxContainer
@export var stat_row_scene: PackedScene
@export var stat_card_scene: PackedScene
@export var style_tab_on: StyleBox
@export var style_tab_off: StyleBox

var _vm: StatisticsViewModel
var _tab: Tab = Tab.RECORDS
var _guard := PressGuard.new()

func _ready() -> void:
	add_child(_guard)
	btn_close.pressed.connect(_on_dismiss_pressed)
	btn_records.pressed.connect(_on_tab_pressed.bind(Tab.RECORDS))
	btn_timeline.pressed.connect(_on_tab_pressed.bind(Tab.TIMELINE))
	btn_runs.pressed.connect(_on_tab_pressed.bind(Tab.RUNS))
	btn_bonuses.pressed.connect(_on_tab_pressed.bind(Tab.BONUSES))
	bind(App.statistics_vm)

func bind(vm: StatisticsViewModel) -> void:
	if _vm:
		_vm.property_changed.disconnect(_on_property_changed)
	_vm = vm
	_vm.property_changed.connect(_on_property_changed)
	_select_tab(_tab)

func _exit_tree() -> void:
	if _vm:
		_vm.property_changed.disconnect(_on_property_changed)
		_vm = null

## Every rebuild here is structural, so all of them go through the guard: a
## sporation resolving under a held finger would otherwise free the row the press
## landed on. See PressGuard.
func _on_property_changed(property: StringName) -> void:
	match property:
		StatisticsViewModel.PROP_RECORDS, StatisticsViewModel.PROP_MILESTONES, \
		StatisticsViewModel.PROP_RUNS, StatisticsViewModel.PROP_BONUSES:
			_guard.run_when_free(&"content", _rebuild)

## Deferred, and for the reason the guard's own `defer` flag exists: this arrives
## from inside a tab button's `pressed` emission, and _rebuild() frees the
## content under it - not the button itself, but close enough to it that running
## inline is not worth the distinction.
func _on_tab_pressed(tab: Tab) -> void:
	_guard.run_when_free(&"content", _select_tab.bind(tab), true)

func _select_tab(tab: Tab) -> void:
	_tab = tab
	_paint_tabs()
	# Only now, so a player who never opens the tab never pays for the walk over
	# every track. Reopening it re-reads, since levels move while it is closed.
	if tab == Tab.BONUSES:
		_vm.refresh_bonuses()
	_rebuild()
	scroll.scroll_vertical = 0

func _paint_tabs() -> void:
	var buttons := [btn_records, btn_timeline, btn_runs, btn_bonuses]
	for i in buttons.size():
		var style: StyleBox = style_tab_on if i == int(_tab) else style_tab_off
		(buttons[i] as Button).add_theme_stylebox_override(&"normal", style)
		(buttons[i] as Button).add_theme_stylebox_override(&"hover", style)
		(buttons[i] as Button).add_theme_stylebox_override(&"pressed", style)

func _rebuild() -> void:
	for child in vbox_content.get_children():
		vbox_content.remove_child(child)
		child.queue_free()
	match _tab:
		Tab.RECORDS:
			_build_records()
		Tab.TIMELINE:
			_build_timeline()
		Tab.RUNS:
			_build_runs()
		Tab.BONUSES:
			_build_bonuses()
	lbl_empty.visible = vbox_content.get_child_count() == 0
	lbl_empty.text = _empty_text()

## What an empty tab says. Three of the four can legitimately be empty on a fresh
## save, and each is empty for its own reason - "nothing here" would leave a
## player wondering whether it is broken.
func _empty_text() -> String:
	match _tab:
		Tab.TIMELINE:
			return "No milestones yet. Unlocking a biome, growing a new node or sporating puts one here."
		Tab.RUNS:
			return "No finished runs yet. The first one lands here when you sporate."
		Tab.BONUSES:
			return "Nothing levelled yet. Bonuses show up here as you buy upgrades."
		_:
			return "No records yet."

func _build_records() -> void:
	for row: Dictionary in _vm.records_rows:
		_add_row(vbox_content, row["label"], row["value"])

func _build_timeline() -> void:
	for row: Dictionary in _vm.milestone_rows:
		var card := _add_card(row["title"], row["when"], row["detail"])
		card.rows.visible = false

func _build_runs() -> void:
	for row: Dictionary in _vm.run_rows:
		var card := _add_card(row["title"], row["when"], "")
		for field: Dictionary in row["fields"]:
			_add_row(card.rows, field["label"], field["value"])

func _build_bonuses() -> void:
	for group: Dictionary in _vm.bonus_groups:
		var card := _add_card(group["resource"], group["total"], group["count"])
		for source: Dictionary in group["sources"]:
			var header := _add_row(card.rows, "", "")
			header.set_header(source["track"])
			for upgrade: Dictionary in source["upgrades"]:
				_add_row(card.rows, upgrade["name"], upgrade["level"])
				for effect: String in upgrade["effects"]:
					var line := _add_row(card.rows, effect, "")
					line.set_muted(true)

func _add_row(parent: VBoxContainer, label: String, value: String) -> Node:
	var row := stat_row_scene.instantiate()
	parent.add_child(row)
	row.set_row(label, value)
	return row

func _add_card(title: String, meta: String, caption: String) -> Node:
	var card := stat_card_scene.instantiate()
	vbox_content.add_child(card)
	card.set_card(title, meta, caption)
	return card

## Presses that reached the backdrop missed the sheet, so they are a tap outside
## the overlay.
func _gui_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button and button.pressed and button.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		_on_dismiss_pressed()

func _on_dismiss_pressed() -> void:
	dismissed.emit()
