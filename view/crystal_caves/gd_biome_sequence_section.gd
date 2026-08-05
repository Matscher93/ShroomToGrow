extends PanelContainer
## VIEW: one biome's section of the Crystal Caves Sequences tab. Holds the upgrade
## sequence the point-spending automation replays for that biome, plus the slot
## grid that appends a step to it.
##
## The grid and its controls are always visible, since recording is what the
## section is for and the grid is a fixed 5x2 either way. Only the recorded steps
## collapse: they are the part that grows without bound, and with one section per
## biome, leaving every list open turns the tab into a wall of steps you have to
## scroll past to reach the next biome. Pressing the section toggles that list.
##
## Bound to a persistent BiomeSequenceViewModel owned by App.

@export var lbl_name: Label
@export var lbl_summary: Label
@export var lbl_status: Label
@export var lbl_empty: Label
@export var expansion_arrow: ColorRect
@export var btn_clear: Button
@export var btn_step_amount: Button
@export var pagination_row: HBoxContainer
@export var btn_page_back: Button
@export var btn_page_forward: Button
@export var lbl_page: Label
@export var vbox_body: VBoxContainer
@export var vbox_steps: VBoxContainer
@export var grid_upgrade_slots: GridContainer
@export var sequence_row_scene: PackedScene

## Same press handling as the biome card: Android and iOS synthesize mouse
## motion from touch, so a scroll drag starts as a press here too.
const TAP_CANCEL_DISTANCE := 10.0

var _vm: BiomeSequenceViewModel
var _expanded := false
var _slot_ids: Array[StringName] = []
var _press_active := false
var _press_start := Vector2.ZERO

func _ready() -> void:
	grid_upgrade_slots.columns = UpgradeSlotGrid.COLUMNS
	btn_clear.pressed.connect(_on_clear_pressed)
	btn_step_amount.pressed.connect(_on_step_amount_pressed)
	btn_page_back.pressed.connect(_on_page_back_pressed)
	btn_page_forward.pressed.connect(_on_page_forward_pressed)
	_apply_expanded()

func bind(vm: BiomeSequenceViewModel) -> void:
	if _vm:
		_vm.property_changed.disconnect(_on_property_changed)
	_vm = vm
	_vm.property_changed.connect(_on_property_changed)
	lbl_name.text = _vm.display_name
	lbl_name.modulate = _vm.biome_color
	_spawn_grid_slots()
	refresh()

func _exit_tree() -> void:
	if _vm:
		_vm.property_changed.disconnect(_on_property_changed)
		_vm = null

func _on_property_changed(_property: StringName) -> void:
	refresh()

func refresh() -> void:
	lbl_summary.text = _vm.summary_text
	lbl_status.text = _vm.status_text
	lbl_status.visible = not lbl_status.text.is_empty()
	btn_step_amount.text = _vm.step_amount_text
	_refresh_grid_slots()
	_rebuild_steps()

# --- Collapsing ---

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_press_active = true
			_press_start = event.position
		elif _press_active:
			_press_active = false
			_toggle_expanded()
	elif event is InputEventMouseMotion and _press_active:
		# Far enough to be a scroll rather than a tap, so cancel it.
		if event.position.distance_to(_press_start) > TAP_CANCEL_DISTANCE:
			_press_active = false

func _toggle_expanded() -> void:
	_expanded = not _expanded
	_apply_expanded()

func _apply_expanded() -> void:
	vbox_body.visible = _expanded
	expansion_arrow.offset_transform_rotation = PI if _expanded else 0.0

# --- Slot grid ---

## The same numbered 5x2 grid the biome card shows, so a slot is in the same
## place on both screens. What it *counts* is different: here it is the levels
## the sequence asks for, not the ones the biome has bought. Pressing one appends
## that upgrade as the next step.
func _spawn_grid_slots() -> void:
	for child in grid_upgrade_slots.get_children():
		grid_upgrade_slots.remove_child(child)
		child.queue_free()
	_slot_ids = _vm.upgrade_ids()
	for i in range(_slot_ids.size()):
		var id: StringName = _slot_ids[i]
		var slot := UpgradeSlotGrid.create_slot(i)
		slot.pressed.connect(_on_slot_pressed.bind(id))
		grid_upgrade_slots.add_child(slot)

## Three states, so the grid reads as a picture of the recording rather than a
## menu: bright for upgrades the sequence already asks for, mid for ones it could
## take next, faint and dead for ones it cannot reach yet.
func _refresh_grid_slots() -> void:
	for i in range(_slot_ids.size()):
		var id: StringName = _slot_ids[i]
		var slot := grid_upgrade_slots.get_child(i) as Button
		UpgradeSlotGrid.set_level_text(slot, _vm.upgrade_slot_text(id))
		var blocked := _vm.record_blocked_reason(id)
		slot.disabled = not blocked.is_empty()
		if _vm.is_recorded(id):
			slot.modulate = Color.WHITE
		elif slot.disabled:
			slot.modulate = UpgradeSlotGrid.UNAVAILABLE_MODULATE
		else:
			slot.modulate = UpgradeSlotGrid.LOCKED_MODULATE
		# The amount can be more than the upgrade's cap has room for, so the
		# tooltip advertises what a press would actually record, not what the
		# selector says.
		slot.tooltip_text = "%s - adds %d" % [_vm.upgrade_name(id), _vm.steps_to_append(id)] \
			if blocked.is_empty() else "%s - %s" % [_vm.upgrade_name(id), blocked]

## Rebuilt wholesale rather than patched: the rows carry their index, so moving
## or removing one shifts every index below it anyway.
##
## Only the current page is spawned, but first/last are judged against the whole
## sequence, so the top row of page two can still be nudged up onto page one.
func _rebuild_steps() -> void:
	for child in vbox_steps.get_children():
		vbox_steps.remove_child(child)
		child.queue_free()
	var total := _vm.step_count
	lbl_empty.visible = total == 0
	btn_clear.disabled = total == 0
	for row_data in _vm.page_rows():
		var row := sequence_row_scene.instantiate()
		vbox_steps.add_child(row)
		var index: int = row_data["index"]
		row.set_row(row_data, index == 0, index == total - 1)
		row.move_up_pressed.connect(_on_move_up)
		row.move_down_pressed.connect(_on_move_down)
		row.remove_pressed.connect(_on_remove)

	pagination_row.visible = _vm.has_pages
	lbl_page.text = _vm.page_text
	btn_page_back.disabled = not _vm.can_page_back
	btn_page_forward.disabled = not _vm.can_page_forward

# --- View -> VM ---

func _on_slot_pressed(id: StringName) -> void:
	_vm.append_step(id)

func _on_step_amount_pressed() -> void:
	_vm.cycle_step_amount()

func _on_page_back_pressed() -> void:
	_vm.page_back()

func _on_page_forward_pressed() -> void:
	_vm.page_forward()

func _on_move_up(index: int) -> void:
	_vm.move_step_up(index)

func _on_move_down(index: int) -> void:
	_vm.move_step_down(index)

func _on_remove(index: int) -> void:
	_vm.remove_step(index)

func _on_clear_pressed() -> void:
	_vm.clear()
