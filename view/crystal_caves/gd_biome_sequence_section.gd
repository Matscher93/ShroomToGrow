extends PanelContainer
## VIEW: one biome's section of the Crystal Caves Sequences tab. Holds the upgrade
## sequence the point-spending automation replays for that biome, the slot grid
## that appends a step to it, and the biome's own auto-buy-after-sporation
## purchase.
##
## The auto-buy sits here rather than with the automation cards because it is
## per-biome the way those are not, and it is bound to the same ViewModel this
## section already holds. One place per biome now covers everything that biome
## does across a sporation.
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
@export var lbl_slot_status: Label
@export var expansion_arrow: ColorRect
@export var auto_unlock_row: HBoxContainer
@export var lbl_auto_unlock: Label
@export var lbl_auto_unlock_cost: Label
@export var btn_auto_unlock_buy: Button
@export var btn_auto_unlock_enabled: CheckButton
@export var btn_clear: Button
@export var btn_remove_last: Button
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

## How long Clear stays armed after the first press. Long enough to be a
## deliberate second tap, short enough that a section left alone cannot be
## cleared by a stray press minutes later.
const CLEAR_CONFIRM_SECONDS := 2.0

var _vm: BiomeSequenceViewModel
var _slot_ids: Array[StringName] = []
var _press_active := false
var _press_start := Vector2.ZERO
## Clear is the one action here that cannot be undone and can throw away
## hundreds of steps, so it takes two presses. Armed state lives on the section
## rather than the VM: it is about this button, and it must not survive the
## screen being rebuilt.
var _clear_armed := false
var _clear_timer: SceneTreeTimer = null

func _ready() -> void:
	grid_upgrade_slots.columns = UpgradeSlotGrid.COLUMNS
	btn_clear.pressed.connect(_on_clear_pressed)
	btn_remove_last.pressed.connect(_on_remove_last_pressed)
	btn_step_amount.pressed.connect(_on_step_amount_pressed)
	btn_page_back.pressed.connect(_on_page_back_pressed)
	btn_page_forward.pressed.connect(_on_page_forward_pressed)
	btn_auto_unlock_buy.pressed.connect(_on_auto_unlock_buy_pressed)
	btn_auto_unlock_enabled.toggled.connect(_on_auto_unlock_toggled)

func bind(vm: BiomeSequenceViewModel) -> void:
	if _vm:
		_vm.property_changed.disconnect(_on_property_changed)
	_vm = vm
	_vm.property_changed.connect(_on_property_changed)
	lbl_name.text = _vm.display_name
	lbl_name.modulate = _vm.biome_color
	# Expansion is parked on the VM, which outlives this screen, so a section
	# opened before a trip to another screen is still open on the way back.
	_apply_expanded()
	_spawn_grid_slots()
	refresh()

func _exit_tree() -> void:
	if _vm:
		_vm.property_changed.disconnect(_on_property_changed)
		_vm = null

## Matched on the property rather than refreshing everything.
##
## refresh() ends in _rebuild_steps(), which frees and re-instantiates up to ten
## row scenes, and summary_text and page_rows() each walk the whole sequence
## again. One upgrades_changed - every automated point spend, every manual
## purchase - lands here three times, because _on_replay_state_changed() notifies
## three properties in a row. Doing the whole refresh for each was rebuilding the
## step list three times over for one change.
func _on_property_changed(property: StringName) -> void:
	match property:
		BiomeSequenceViewModel.PROP_SEQUENCE_CHANGED:
			_refresh_grid_slots()
			_rebuild_steps()
		BiomeSequenceViewModel.PROP_SUMMARY_TEXT:
			lbl_summary.text = _vm.summary_text
			lbl_status.text = _vm.status_text
			lbl_status.visible = not lbl_status.text.is_empty()
		BiomeSequenceViewModel.PROP_STEP_AMOUNT:
			btn_step_amount.text = _vm.step_amount_text
		BiomeSequenceViewModel.PROP_AUTO_UNLOCK:
			_refresh_auto_unlock()
		BiomeSequenceViewModel.PROP_SLOT_STATUS:
			lbl_slot_status.text = _vm.slot_status_text
			lbl_slot_status.visible = not lbl_slot_status.text.is_empty()

func refresh() -> void:
	lbl_summary.text = _vm.summary_text
	lbl_status.text = _vm.status_text
	lbl_status.visible = not lbl_status.text.is_empty()
	lbl_slot_status.text = _vm.slot_status_text
	lbl_slot_status.visible = not lbl_slot_status.text.is_empty()
	btn_step_amount.text = _vm.step_amount_text
	_refresh_auto_unlock()
	_refresh_grid_slots()
	_rebuild_steps()

# --- Collapsing ---

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			# The step list must not collapse the section, but its rows cannot be
			# MOUSE_FILTER_STOP either - that would eat the scroll drags the
			# ScrollContainer above needs. The rows pass events on instead, and
			# the tap is rejected here, by where it landed.
			_press_active = not _is_in_body(event.global_position)
			_press_start = event.position
		elif _press_active:
			_press_active = false
			_toggle_expanded()
	elif event is InputEventMouseMotion and _press_active:
		# Far enough to be a scroll rather than a tap, so cancel it.
		if event.position.distance_to(_press_start) > TAP_CANCEL_DISTANCE:
			_press_active = false

func _is_in_body(global_pos: Vector2) -> bool:
	return vbox_body.visible and vbox_body.get_global_rect().has_point(global_pos)

func _toggle_expanded() -> void:
	_vm.expanded = not _vm.expanded
	_apply_expanded()

func _apply_expanded() -> void:
	vbox_body.visible = _vm.expanded
	expansion_arrow.offset_transform_rotation = PI if _vm.expanded else 0.0

# --- Auto-buy after sporation ---

## Buy and switch are never both up: the purchase is one-off, so its button gives
## way to the switch it unlocks rather than sitting there disabled forever. The
## prose line says which of "never bought" and "switched off" is in force, since
## the Buy button is gone in both cases.
##
## A starter biome never relocks, so it gets no row at all rather than one that
## can only ever say so.
func _refresh_auto_unlock() -> void:
	auto_unlock_row.visible = _vm.offers_auto_unlock
	if not _vm.offers_auto_unlock:
		return
	lbl_auto_unlock.text = _vm.auto_unlock_text
	var for_sale := not _vm.has_auto_unlock
	lbl_auto_unlock_cost.visible = for_sale
	btn_auto_unlock_buy.visible = for_sale
	btn_auto_unlock_enabled.visible = not for_sale
	if for_sale:
		lbl_auto_unlock_cost.text = _vm.auto_unlock_cost_text
		btn_auto_unlock_buy.disabled = not _vm.can_buy_auto_unlock
	else:
		# No-signal, or every refresh would report a toggle back at the model and
		# fight whatever just changed.
		btn_auto_unlock_enabled.set_pressed_no_signal(_vm.auto_unlock_enabled)

# --- Slot grid ---

## The same numbered 5x2 grid the biome card shows, so a slot is in the same
## place on both screens. What it *counts* is different - here it is the levels
## the sequence asks for, not the ones the biome has bought - which is what the
## caption above the grid is there to say. Pressing one appends that upgrade as
## the next step.
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
## take next, faint for ones it cannot reach yet.
##
## A blocked slot is dimmed but deliberately still pressable. Godot swallows
## input on a disabled Button, and pressing a blocked slot is how the status line
## below is asked why it is blocked - the reason used to be a tooltip, which does
## not exist on touch. Nothing can be recorded by mistake: append_step records
## steps_to_append(), which is zero for exactly these slots.
##
## The whole grid does go dead for a biome that is shut this run. Its section is
## still listed so the auto-buy above can be bought, but there is nothing to plan
## against until the biome is back.
func _refresh_grid_slots() -> void:
	var biome_open := _vm.is_unlocked
	for i in range(_slot_ids.size()):
		var id: StringName = _slot_ids[i]
		var slot := grid_upgrade_slots.get_child(i) as Button
		UpgradeSlotGrid.set_level_text(slot, _vm.upgrade_slot_text(id))
		slot.disabled = not biome_open
		if not biome_open:
			slot.modulate = UpgradeSlotGrid.UNAVAILABLE_MODULATE
		elif _vm.is_recorded(id):
			slot.modulate = Color.WHITE
		elif _vm.can_record(id):
			slot.modulate = UpgradeSlotGrid.LOCKED_MODULATE
		else:
			slot.modulate = UpgradeSlotGrid.UNAVAILABLE_MODULATE

## Rebuilt wholesale rather than patched: only the current page is spawned, and
## a step added or dropped shifts which steps that is.
func _rebuild_steps() -> void:
	for child in vbox_steps.get_children():
		vbox_steps.remove_child(child)
		child.queue_free()
	var total := _vm.step_count
	lbl_empty.visible = total == 0
	btn_remove_last.disabled = total == 0
	btn_clear.disabled = total == 0
	# An emptied sequence has nothing left to confirm away.
	if total == 0:
		_disarm_clear()
	for row_data in _vm.page_rows():
		var row := sequence_row_scene.instantiate()
		vbox_steps.add_child(row)
		row.set_row(row_data)

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

func _on_remove_last_pressed() -> void:
	_vm.remove_last()

func _on_auto_unlock_buy_pressed() -> void:
	_vm.buy_auto_unlock()

func _on_auto_unlock_toggled(_pressed: bool) -> void:
	_vm.toggle_auto_unlock()

## First press arms, second within the window clears. The timer disarms on its
## own, so a section left alone goes back to a plain Clear rather than sitting
## one stray tap away from wiping the sequence.
func _on_clear_pressed() -> void:
	if _clear_armed:
		_disarm_clear()
		_vm.clear()
		return
	_clear_armed = true
	btn_clear.text = "Sure?"
	# Tracked so a re-arm inside the window can drop the timer already running.
	# Each press used to leave its own connected, and the older one would then
	# disarm the button partway through the new window.
	_clear_timer = get_tree().create_timer(CLEAR_CONFIRM_SECONDS)
	_clear_timer.timeout.connect(_on_clear_timeout.bind(_clear_timer))

## Ignored unless this is still the timer the button is waiting on.
func _on_clear_timeout(timer: SceneTreeTimer) -> void:
	if timer != _clear_timer:
		return
	_disarm_clear()

func _disarm_clear() -> void:
	_clear_armed = false
	_clear_timer = null
	btn_clear.text = "Clear"
