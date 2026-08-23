@tool
extends PanelContainer

@export var color_param: String
@export var upgrade_button: Button
@export var owned_nodes: Label
@export var manual_nodes: Label
@export var level_value: Label
@export var level_header: Label
@export var label_node_name: Label
@export var label_node_desc: Label
@export var label_node_income: Label
@export var label_buy_cost: Label
@export var panel_buy_node: PanelContainer
@export var level_icon: ColorRect
@export var vbox_synergy: VBoxContainer
@export var vbox_buy: VBoxContainer
@export var expansion_arrow: ColorRect
@export var label_yield: Label
@export var label_total_yield: Label
@export var label_potency_level: Label
@export var label_potency_gain_header: Label
@export var label_potency_accumulated: Label
@export var label_potency_cost: Label
@export var panel_potency: PanelContainer
@export var upgrade_button_potency: Button
@export var label_synergy_level: Label
@export var label_synergy_gain_header: Label
@export var label_synergy_accumulated: Label
@export var label_synergy_cost: Label
@export var panel_synergy: PanelContainer
@export var upgrade_button_synergy: Button
@export var node_level: int = 0
var _vm: MyceliumNodeViewModel

const TAP_CANCEL_DISTANCE := 10.0  # px, beyond this a press is a scroll drag, not a tap
var _press_active := false
var _press_start := Vector2.ZERO

func _ready() -> void:
	_update_shader()
	vbox_synergy.visible = false
	vbox_buy.visible = false
	expansion_arrow.offset_transform_rotation = 0.0

	# Autoloads aren't instantiated for @tool scripts in the editor, and
	# everything below needs the live game state from App.
	if Engine.is_editor_hint():
		return

	upgrade_button.pressed.connect(_on_upgrade_pressed)
	upgrade_button_potency.pressed.connect(_on_buy_potency_pressed)
	upgrade_button_synergy.pressed.connect(_on_buy_synergy_pressed)
	if node_level < App.mycelium_node_vms.size():
		bind(App.mycelium_node_vms[node_level])

func bind(vm: MyceliumNodeViewModel) -> void:
	if _vm:
		_vm.property_changed.disconnect(_on_property_changed)
	_vm = vm
	_vm.property_changed.connect(_on_property_changed)
	_refresh_all()

func _exit_tree() -> void:
	if _vm:
		_vm.property_changed.disconnect(_on_property_changed)
		_vm = null

# --- VM -> View ---

func _on_property_changed(property: StringName) -> void:
	match property:
		MyceliumNodeViewModel.PROP_BUY_TEXT:
			label_buy_cost.text = _vm.buy_button_text
		MyceliumNodeViewModel.PROP_CAN_BUY:
			panel_buy_node.set_enabled(_vm.can_buy_upgrade)
		MyceliumNodeViewModel.PROP_OWNED_NODE_TEXT:
			owned_nodes.text =_vm.owned_node_text
		MyceliumNodeViewModel.PROP_MANUAL_NODE_TEXT:
			manual_nodes.text = _vm.manual_node_text
		MyceliumNodeViewModel.PROP_PRODUCTION_TEXT:
			label_node_income.text = _vm.production_text
			label_node_desc.text = _vm.production_per_node_text
		MyceliumNodeViewModel.PROP_SYMBIOSIS_YIELD_TEXT:
			label_yield.text = _vm.symbiosis_yield_text
		MyceliumNodeViewModel.PROP_TOTAL_YIELD_TEXT:
			label_total_yield.text = _vm.total_yield_text
		MyceliumNodeViewModel.PROP_POTENCY_LEVEL_TEXT:
			label_potency_level.text = _vm.potency_level_text
		MyceliumNodeViewModel.PROP_POTENCY_HEADER_TEXT:
			label_potency_gain_header.text = _vm.potency_header_text
		MyceliumNodeViewModel.PROP_POTENCY_ACCUMULATED_TEXT:
			label_potency_accumulated.text = _vm.potency_accumulated_text
		MyceliumNodeViewModel.PROP_POTENCY_COST_TEXT:
			label_potency_cost.text = _vm.potency_cost_text
		MyceliumNodeViewModel.PROP_POTENCY_CAN_BUY:
			upgrade_button_potency.disabled = not _vm.potency_can_buy
			panel_potency.set_enabled(_vm.potency_can_buy)
		MyceliumNodeViewModel.PROP_SYNERGY_LEVEL_TEXT:
			label_synergy_level.text = _vm.synergy_level_text
		MyceliumNodeViewModel.PROP_SYNERGY_HEADER_TEXT:
			label_synergy_gain_header.text = _vm.synergy_header_text
		MyceliumNodeViewModel.PROP_SYNERGY_ACCUMULATED_TEXT:
			label_synergy_accumulated.text = _vm.synergy_accumulated_text
		MyceliumNodeViewModel.PROP_SYNERGY_COST_TEXT:
			label_synergy_cost.text = _vm.synergy_cost_text
		MyceliumNodeViewModel.PROP_SYNERGY_CAN_BUY:
			upgrade_button_synergy.disabled = not _vm.synergy_can_buy
			panel_synergy.set_enabled(_vm.synergy_can_buy)

func _refresh_all() -> void:
	label_buy_cost.text = _vm.buy_button_text
	panel_buy_node.set_enabled(_vm.can_buy_upgrade)
	owned_nodes.text =_vm.owned_node_text
	manual_nodes.text = _vm.manual_node_text
	label_node_income.text = _vm.production_text
	level_value.text = "%d" % [node_level + 1]
	label_node_name.text = _vm.node_name
	label_node_desc.text = _vm.production_per_node_text
	label_yield.text = _vm.symbiosis_yield_text
	label_total_yield.text = _vm.total_yield_text
	_refresh_upgrade_labels()
	_apply_colors()

func _refresh_upgrade_labels() -> void:
	label_potency_level.text = _vm.potency_level_text
	label_potency_gain_header.text = _vm.potency_header_text
	label_potency_accumulated.text = _vm.potency_accumulated_text
	label_potency_cost.text = _vm.potency_cost_text
	upgrade_button_potency.disabled = not _vm.potency_can_buy
	panel_potency.set_enabled(_vm.potency_can_buy)
	label_synergy_level.text = _vm.synergy_level_text
	label_synergy_gain_header.text = _vm.synergy_header_text
	label_synergy_accumulated.text = _vm.synergy_accumulated_text
	label_synergy_cost.text = _vm.synergy_cost_text
	upgrade_button_synergy.disabled = not _vm.synergy_can_buy
	panel_synergy.set_enabled(_vm.synergy_can_buy)

# --- View -> VM ---

func _on_upgrade_pressed() -> void:
	_vm.buy_upgrade()

func _on_buy_potency_pressed() -> void:
	_vm.buy_potency()

func _on_buy_synergy_pressed() -> void:
	_vm.buy_synergy()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			# The synergy block must not collapse the card, but it cannot be
			# MOUSE_FILTER_STOP either - that would eat the scroll drags the
			# ScrollContainer above needs. It passes events on instead, and the
			# tap is rejected here, by where it landed.
			_press_active = not _is_in_synergy(event.global_position)
			_press_start = event.position
		elif _press_active:
			_press_active = false
			_toggle_synergy()
	elif event is InputEventMouseMotion and _press_active:
		# Android/iOS synthesize mouse motion from touch, so a scroll drag
		# starts as a press here too. Cancel the tap once it moves far enough
		# to be a scroll.
		if event.position.distance_to(_press_start) > TAP_CANCEL_DISTANCE:
			_press_active = false

func _is_in_synergy(global_pos: Vector2) -> bool:
	return vbox_synergy.visible and vbox_synergy.get_global_rect().has_point(global_pos)

func _toggle_synergy() -> void:
	if _vm == null: return
	vbox_buy.visible = not vbox_buy.visible
	expansion_arrow.offset_transform_rotation = PI if vbox_buy.visible else 0.0
	if _vm.synergy_track_unlocked:
		vbox_synergy.visible = vbox_buy.visible
	else:
		vbox_synergy.visible = false

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_update_shader()

func _update_shader() -> void:
	if material:
		material.set_shader_parameter("rect_size", size * get_global_transform().get_scale())

func _apply_colors() -> void:
	if material:
		material.set_shader_parameter(color_param, _vm.node_color)
		level_icon.set_shader_color(_vm.node_color)
		panel_buy_node.set_shader_color(_vm.node_color)
		panel_potency.set_shader_color(_vm.node_color)
		panel_synergy.set_shader_color(_vm.node_color)
		var color_level_text := _vm.node_level_font_color
		var color_main_text := Color.from_hsv(color_level_text.h, 0.7, 0.8)

		level_value.label_settings = level_value.label_settings.duplicate()
		level_header.label_settings = level_header.label_settings.duplicate()
		label_node_name.label_settings = label_node_name.label_settings.duplicate()
		owned_nodes.label_settings = owned_nodes.label_settings.duplicate()
		manual_nodes.label_settings = manual_nodes.label_settings.duplicate()
		label_node_income.label_settings = label_node_income.label_settings.duplicate()

		level_value.label_settings.font_color = color_level_text
		level_header.label_settings.font_color = color_level_text
		label_node_name.label_settings.font_color = color_main_text
		owned_nodes.label_settings.font_color = color_main_text
		manual_nodes.label_settings.font_color = color_main_text
		label_node_income.label_settings.font_color = color_main_text
