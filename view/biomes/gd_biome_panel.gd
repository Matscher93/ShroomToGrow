@tool
class_name BiomePanel
extends PanelContainer
## VIEW — one biome's card: name/desc, current level badge, XP progress,
## unlock action, Biome Size, and its 10 point-bought upgrades. Spawned once
## per BiomeDef by BiomesPanel (gd_biomes_panel.gd), which sets biome_key
## right after instantiating; binds itself to App.biome_vms[biome_key] in
## _ready. The 10 upgrades show as a 5x2 grid of small selectable slot
## buttons (spawned at runtime, one per App.biome_upgrade_ids(), same pattern
## as gd_nodes_panel.gd); picking one rebinds the single upgrade_detail card
## (sc_biome_upgrade_card.tscn, embedded statically) to show its info and let
## you buy levels for it.

@export var color_param: String
@export var biome_key: StringName

const GRID_COLUMNS := 5
const LOCKED_MODULATE := Color(1, 1, 1, 0.4)
var _slot_group := ButtonGroup.new()
var _slot_ids: Array[StringName] = []

@export var level_icon: ColorRect
@export var lbl_biome_name: Label
@export var lbl_biome_desc: Label
@export var panel_level_badge: PanelContainer
@export var lbl_level_badge: Label
@export var image_notification: ColorRect
@export var expansion_arrow: ColorRect

@export var vbox_buy: VBoxContainer
@export var lbl_unlock_info: Label
@export var panel_unlock_biome: PanelContainer
@export var lbl_unlock_cost: Label
@export var unlock_biome_button: Button

@export var vbox_upgrades: VBoxContainer
@export var lbl_biome_progress: Label
@export var image_biome_progress: ColorRect

@export var panel_biome_size: PanelContainer
@export var lbl_size_level: Label
@export var lbl_size_desc: Label
@export var panel_buy_size: PanelContainer
@export var lbl_size_cost: Label
@export var size_buy_button: Button

@export var lbl_upgrade_points: Label
@export var grid_upgrade_slots: GridContainer
@export var upgrade_detail: BiomeUpgradeCard

var _vm: BiomeViewModel
var _expanded := true

const TAP_CANCEL_DISTANCE := 10.0  # px — beyond this, a press is a scroll drag, not a tap
var _press_active := false
var _press_start := Vector2.ZERO

func _ready() -> void:
	_update_shader()
	expansion_arrow.offset_transform_rotation = 0.0

	lbl_size_desc.text = "Scales size-dependent upgrades"

	grid_upgrade_slots.columns = GRID_COLUMNS

	# App is an autoload, and autoloads aren't instantiated for @tool scripts
	# running in the editor — everything below needs the live game state.
	if Engine.is_editor_hint():
		return

	unlock_biome_button.pressed.connect(_on_unlock_pressed)
	size_buy_button.pressed.connect(_on_buy_size_pressed)
	App.biome_upgrade_system.upgrades_changed.connect(_refresh_grid_lock_state)

	_spawn_grid_slots()

	if App.biome_vms.has(biome_key):
		bind(App.biome_vms[biome_key])

func _spawn_grid_slots() -> void:
	for child in grid_upgrade_slots.get_children():
		grid_upgrade_slots.remove_child(child)
		child.queue_free()
	_slot_ids = App.biome_upgrade_ids(biome_key)
	for i in range(_slot_ids.size()):
		var id: StringName = _slot_ids[i]
		var btn := Button.new()
		btn.text = str(i + 1)
		btn.custom_minimum_size = Vector2(36, 32)
		btn.toggle_mode = true
		btn.button_group = _slot_group
		btn.add_theme_stylebox_override("normal", _slot_style(Color(1, 1, 1, 0.08)))
		btn.add_theme_stylebox_override("hover", _slot_style(Color(1, 1, 1, 0.16)))
		btn.add_theme_stylebox_override("pressed", _slot_style(Color(1, 1, 1, 0.32)))
		btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		btn.toggled.connect(func(on: bool) -> void:
			if on:
				_on_slot_selected(id))
		grid_upgrade_slots.add_child(btn)
	if not _slot_ids.is_empty():
		(grid_upgrade_slots.get_child(0) as Button).button_pressed = true
		_on_slot_selected(_slot_ids[0])
	_refresh_grid_lock_state()

func _refresh_grid_lock_state() -> void:
	for i in range(_slot_ids.size()):
		var btn := grid_upgrade_slots.get_child(i) as Button
		var unlocked := App.is_biome_upgrade_unlocked(_slot_ids[i], biome_key)
		btn.modulate = Color.WHITE if unlocked else LOCKED_MODULATE

func _slot_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	return style

func _on_slot_selected(id: StringName) -> void:
	upgrade_detail.select_upgrade(id, biome_key)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_press_active = true
			_press_start = event.position
		elif _press_active:
			_press_active = false
			_toggle_upgrades()
	elif event is InputEventMouseMotion and _press_active:
		# Android/iOS synthesize mouse motion from touch — a real scroll drag
		# starts as a press here too, so cancel the tap once it moves enough
		# to be a scroll rather than a tap.
		if event.position.distance_to(_press_start) > TAP_CANCEL_DISTANCE:
			_press_active = false

func _toggle_upgrades() -> void:
	if not _vm or not _vm.unlocked:
		return
	_expanded = not _expanded
	vbox_upgrades.visible = _expanded
	expansion_arrow.offset_transform_rotation = PI if _expanded else 0.0

func bind(vm: BiomeViewModel) -> void:
	if _vm:
		_vm.property_changed.disconnect(_on_property_changed)
	_vm = vm
	_vm.property_changed.connect(_on_property_changed)
	_refresh_all()

func _exit_tree() -> void:
	if _vm:
		_vm.property_changed.disconnect(_on_property_changed)
		_vm = null
	if Engine.is_editor_hint():
		return
	if App.biome_upgrade_system.upgrades_changed.is_connected(_refresh_grid_lock_state):
		App.biome_upgrade_system.upgrades_changed.disconnect(_refresh_grid_lock_state)

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_update_shader()

func _update_shader() -> void:
	if material:
		material.set_shader_parameter("rect_size", size * get_global_transform().get_scale())

# --- VM -> View ---

func _on_property_changed(property: StringName) -> void:
	match property:
		BiomeViewModel.PROP_UNLOCKED:
			_refresh_unlock_section()
		BiomeViewModel.PROP_CAN_UNLOCK:
			panel_unlock_biome.set_enabled(_vm.can_unlock)
		BiomeViewModel.PROP_LEVEL_TEXT:
			lbl_level_badge.text = _vm.level_text
		BiomeViewModel.PROP_PROGRESS_TEXT:
			lbl_biome_progress.text = _vm.progress_text
		BiomeViewModel.PROP_PROGRESS_RATIO:
			_set_progress_ratio(_vm.progress_ratio)
		BiomeViewModel.PROP_POINTS_TEXT:
			lbl_upgrade_points.text = _vm.points_text
		BiomeViewModel.PROP_HAS_POINTS:
			image_notification.visible = _vm.has_points
		BiomeViewModel.PROP_SIZE_LEVEL_TEXT, BiomeViewModel.PROP_SIZE_COST_TEXT, BiomeViewModel.PROP_CAN_BUY_SIZE:
			_refresh_size_section()

func _refresh_unlock_section() -> void:
	vbox_buy.visible = not _vm.unlocked
	vbox_upgrades.visible = _vm.unlocked and _expanded
	if not _vm.unlocked:
		lbl_unlock_info.text = _vm.unlock_info_text
		lbl_unlock_cost.text = _vm.unlock_cost_text
		panel_unlock_biome.set_enabled(_vm.can_unlock)

func _refresh_size_section() -> void:
	lbl_size_level.text = _vm.size_level_text
	lbl_size_cost.text = _vm.size_cost_text
	size_buy_button.disabled = not _vm.can_buy_size
	panel_buy_size.set_enabled(_vm.can_buy_size)

func _set_progress_ratio(ratio: float) -> void:
	if image_biome_progress.material:
		image_biome_progress.material.set_shader_parameter("fill_color", _vm.biome_color)
		image_biome_progress.material.set_shader_parameter("tick_progress", ratio)

func _refresh_all() -> void:
	lbl_biome_name.text = _vm.display_name
	lbl_biome_desc.text = _vm.description
	level_icon._set_shader(_vm.biome_shader)
	level_icon._set_color(_vm.biome_color)
	panel_level_badge._set_color(_vm.biome_color)
	panel_buy_size._set_color(_vm.biome_color)
	upgrade_detail._set_color(_vm.biome_color)
	if material:
		material.set_shader_parameter(color_param, _vm.biome_color)

	lbl_level_badge.text = _vm.level_text
	_refresh_unlock_section()

	lbl_biome_progress.text = _vm.progress_text
	_set_progress_ratio(_vm.progress_ratio)

	lbl_upgrade_points.text = _vm.points_text
	image_notification.visible = _vm.has_points

	_refresh_size_section()

# --- View -> VM ---

func _on_unlock_pressed() -> void:
	_vm.unlock()

func _on_buy_size_pressed() -> void:
	_vm.buy_size()
