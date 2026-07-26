@tool
class_name BiomePanel
extends PanelContainer
## VIEW — one biome's card: name/desc, current level badge, XP progress,
## unlock action, and its single point-bought upgrade. Spawned once per
## BiomeDef by BiomesPanel (gd_biomes_panel.gd), which sets biome_key right
## after instantiating; binds itself to App.biome_vms[biome_key] in _ready.
##
## "Biome Size" (panel_biome_size / panel_buy_size) is a stat the design
## calls for — it'll boost upgrade effectiveness — but nothing backs it yet
## (no BiomeDef field, no purchase path), so its buy button stays permanently
## disabled here until that model exists.

@export var color_param: String
@export var biome_key: StringName

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

@export var lbl_upgrade_points: Label
@export var panel_upgrade_card: PanelContainer
@export var lbl_upgrade_name: Label
@export var lbl_upgrade_level: Label
@export var lbl_upgrade_effect: Label
@export var panel_buy_upgrade: PanelContainer
@export var lbl_upgrade_cost: Label
@export var upgrade_buy_button: Button

var _vm: BiomeViewModel
var _expanded := true

const TAP_CANCEL_DISTANCE := 10.0  # px — beyond this, a press is a scroll drag, not a tap
var _press_active := false
var _press_start := Vector2.ZERO

func _ready() -> void:
	_update_shader()
	expansion_arrow.offset_transform_rotation = 0.0

	# "Biome Size" has no backing stat yet — keep it visible but locked.
	panel_buy_size.set_enabled(false)
	lbl_size_level.text = "—"
	lbl_size_desc.text = "Coming soon"

	unlock_biome_button.pressed.connect(_on_unlock_pressed)
	upgrade_buy_button.pressed.connect(_on_buy_upgrade_pressed)

	if App.biome_vms.has(biome_key):
		bind(App.biome_vms[biome_key])

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
		BiomeViewModel.PROP_UPGRADE_LEVEL_TEXT:
			lbl_upgrade_level.text = _vm.upgrade_level_text
		BiomeViewModel.PROP_UPGRADE_EFFECT_TEXT:
			lbl_upgrade_effect.text = _vm.upgrade_effect_text
		BiomeViewModel.PROP_CAN_BUY_UPGRADE:
			panel_buy_upgrade.set_enabled(_vm.can_buy_upgrade)

func _refresh_unlock_section() -> void:
	vbox_buy.visible = not _vm.unlocked
	vbox_upgrades.visible = _vm.unlocked and _expanded
	if not _vm.unlocked:
		lbl_unlock_info.text = _vm.unlock_info_text
		lbl_unlock_cost.text = _vm.unlock_cost_text
		panel_unlock_biome.set_enabled(_vm.can_unlock)

func _set_progress_ratio(ratio: float) -> void:
	if image_biome_progress.material:
		image_biome_progress.material.set_shader_parameter("fill_color", _vm.biome_color)
		image_biome_progress.material.set_shader_parameter("tick_progress", ratio)

func _refresh_all() -> void:
	lbl_biome_name.text = _vm.display_name
	lbl_biome_desc.text = _vm.description
	level_icon._set_color(_vm.biome_color)
	panel_level_badge._set_color(_vm.biome_color)
	panel_upgrade_card._set_color(_vm.biome_color)
	panel_buy_size._set_color(_vm.biome_color)
	panel_buy_upgrade._set_color(_vm.biome_color)
	if material:
		material.set_shader_parameter(color_param, _vm.biome_color)

	lbl_level_badge.text = _vm.level_text
	_refresh_unlock_section()

	lbl_biome_progress.text = _vm.progress_text
	_set_progress_ratio(_vm.progress_ratio)

	lbl_upgrade_points.text = _vm.points_text
	image_notification.visible = _vm.has_points

	lbl_upgrade_name.text = _vm.upgrade_name
	lbl_upgrade_level.text = _vm.upgrade_level_text
	lbl_upgrade_effect.text = _vm.upgrade_effect_text
	lbl_upgrade_cost.text = "1 pt"
	panel_buy_upgrade.set_enabled(_vm.can_buy_upgrade)

# --- View -> VM ---

func _on_unlock_pressed() -> void:
	_vm.unlock()

func _on_buy_upgrade_pressed() -> void:
	_vm.buy_upgrade()
