extends PanelContainer
## VIEW: the sheet that fills an empty place on the board - every mission that
## could go in it, each with the creature best placed to take it already picked.
##
## A sheet rather than a list on the screen behind it, for the reason the board is
## built out of slots at all: the ladder has dozens of missions and the board has
## a handful of places, so a screen showing both makes the player hunt through the
## first to reach the second. Here the hunting happens once, on purpose, when
## there is a place to fill.
##
## The root is the dimmed backdrop; tapping it closes, exactly like the close
## button. The sheet inside it is a PanelContainer, so it swallows its own presses
## and a tap on a row never reaches the backdrop. Same shape as the events sheet.

## Emitted when the player dismisses the sheet. Whoever spawned this instance
## owns freeing it. This view never queue_frees itself, so it can't desync the
## PopupLayer's tracked ref.
signal dismissed

@export var lbl_title: Label
@export var lbl_empty: Label
@export var btn_close: Button
@export var vbox_missions: VBoxContainer
@export var choice_row_scene: PackedScene

## Which board this sheet is filling. Written through set_board() rather than
## directly: PopupLayer.show_popup() parents the sheet as it creates it, so
## _ready() has already run by the time the panel gets the reference back and
## there is no window in which to set a field before it is read.
var is_farm := false

var _vm: RuinsViewModel

func _ready() -> void:
	btn_close.pressed.connect(_on_dismiss_pressed)
	gui_input.connect(_on_backdrop_input)
	bind(App.ruins_vm)

func bind(vm: RuinsViewModel) -> void:
	if _vm:
		_vm.property_changed.disconnect(_on_property_changed)
	_vm = vm
	_vm.property_changed.connect(_on_property_changed)
	_refresh()

## Says which of the two boards is being filled. The panel calls this straight
## after showing the sheet, and it is what fills the list.
func set_board(value: bool) -> void:
	is_farm = value
	_refresh()

func _refresh() -> void:
	if _vm == null:
		return
	lbl_title.text = "Assign a farm" if is_farm else "Send an expedition"
	_build_rows()

func _exit_tree() -> void:
	if _vm:
		_vm.property_changed.disconnect(_on_property_changed)
		_vm = null

# --- VM -> View ---

func _on_property_changed(property: StringName) -> void:
	if property != RuinsViewModel.PROP_BOARD_CHANGED:
		return
	_build_rows()

func _build_rows() -> void:
	for child in vbox_missions.get_children():
		vbox_missions.remove_child(child)
		child.queue_free()
	var rows := _vm.sendable_missions(is_farm)
	for vm in rows:
		var row := choice_row_scene.instantiate()
		vbox_missions.add_child(row)
		row.bind(vm)
		row.chosen.connect(_on_chosen)
	lbl_empty.visible = rows.is_empty()
	lbl_empty.text = "Nothing to farm yet. Finish an expedition to open one." if is_farm \
		else "Every expedition is out or already run."

# --- View -> VM ---

## One tap fills the slot and closes the sheet: the player opened this to make one
## choice, and leaving it up afterwards would ask them to close it as well.
func _on_chosen(vm: MissionViewModel, creature_id: StringName) -> void:
	if not vm.start(creature_id):
		return
	dismissed.emit()

func _on_dismiss_pressed() -> void:
	dismissed.emit()

## A tap on the backdrop, meaning outside the sheet, closes it.
func _on_backdrop_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		dismissed.emit()
		return
	if event is InputEventScreenTouch and event.pressed:
		dismissed.emit()
