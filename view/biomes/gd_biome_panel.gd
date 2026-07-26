@tool
class_name BiomePanel
extends PanelContainer
## VIEW — one biome's card: name/desc, current level badge, XP progress,
## unlock action, Biome Size, and its 10 point-bought upgrades. Spawned once
## per BiomeDef by BiomesPanel (gd_biomes_panel.gd), which sets biome_key
## right after instantiating; binds itself to App.biome_vms[biome_key] in
## _ready. Upgrade cards are spawned at runtime (one per App.biome_upgrade_ids())
## into vbox_upgrade_cards, same pattern as gd_nodes_panel.gd.

@export var color_param: String
@export var biome_key: StringName
@export var upgrade_card_scene: PackedScene

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
@export var vbox_upgrade_cards: VBoxContainer

var _vm: BiomeViewModel
var _expanded := true

const TAP_CANCEL_DISTANCE := 10.0  # px — beyond this, a press is a scroll drag, not a tap
var _press_active := false
var _press_start := Vector2.ZERO

func _ready() -> void:
	_update_shader()
	expansion_arrow.offset_transform_rotation = 0.0

	lbl_size_desc.text = "Scales size-dependent upgrades"

	unlock_biome_button.pressed.connect(_on_unlock_pressed)
	size_buy_button.pressed.connect(_on_buy_size_pressed)
	App.biome_size_changed.connect(_on_biome_size_changed)
	App.player_data.nutrients_changed.connect(_on_nutrients_changed)

	_spawn_upgrade_cards()

	if App.biome_vms.has(biome_key):
		bind(App.biome_vms[biome_key])

func _spawn_upgrade_cards() -> void:
	for child in vbox_upgrade_cards.get_children():
		vbox_upgrade_cards.remove_child(child)
		child.queue_free()
	for id in App.biome_upgrade_ids(biome_key):
		var card = upgrade_card_scene.instantiate()
		card.upgrade_id = id
		card.biome_key = biome_key
		vbox_upgrade_cards.add_child(card)

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
	if App.biome_size_changed.is_connected(_on_biome_size_changed):
		App.biome_size_changed.disconnect(_on_biome_size_changed)
	if App.player_data.nutrients_changed.is_connected(_on_nutrients_changed):
		App.player_data.nutrients_changed.disconnect(_on_nutrients_changed)

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

func _on_biome_size_changed(key: StringName) -> void:
	if key == biome_key:
		_refresh_size_section()

func _on_nutrients_changed(_value: BigNumber) -> void:
	_refresh_size_section()

func _refresh_unlock_section() -> void:
	vbox_buy.visible = not _vm.unlocked
	vbox_upgrades.visible = _vm.unlocked and _expanded
	if not _vm.unlocked:
		lbl_unlock_info.text = _vm.unlock_info_text
		lbl_unlock_cost.text = _vm.unlock_cost_text
		panel_unlock_biome.set_enabled(_vm.can_unlock)

func _refresh_size_section() -> void:
	lbl_size_level.text = "Lv %d" % App.biome_size(biome_key)
	lbl_size_cost.text = App.biome_size_cost(biome_key)._to_string()
	var can_buy := App.can_buy_biome_size(biome_key)
	size_buy_button.disabled = not can_buy
	panel_buy_size.set_enabled(can_buy)

func _set_progress_ratio(ratio: float) -> void:
	if image_biome_progress.material:
		image_biome_progress.material.set_shader_parameter("fill_color", _vm.biome_color)
		image_biome_progress.material.set_shader_parameter("tick_progress", ratio)

func _refresh_all() -> void:
	lbl_biome_name.text = _vm.display_name
	lbl_biome_desc.text = _vm.description
	level_icon._set_color(_vm.biome_color)
	panel_level_badge._set_color(_vm.biome_color)
	panel_buy_size._set_color(_vm.biome_color)
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
	App.buy_biome_size(biome_key)
