@tool
class_name MyceliumNodePanel
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
var _potency_id: StringName
var _synergy_id: StringName

const TAP_CANCEL_DISTANCE := 10.0  # px — beyond this, a press is a scroll drag, not a tap
var _press_active := false
var _press_start := Vector2.ZERO

func _ready() -> void:
	_update_shader()
	vbox_synergy.visible = false
	vbox_buy.visible = false
	expansion_arrow.offset_transform_rotation = 0.0
	upgrade_button.pressed.connect(_on_upgrade_pressed)
	_potency_id = StringName("NodePotency%d" % node_level)
	_synergy_id = StringName("NodeSynergy%d" % node_level)
	upgrade_button_potency.pressed.connect(_on_buy_potency_pressed)
	upgrade_button_synergy.pressed.connect(_on_buy_synergy_pressed)
	App.upgrade_system.upgrades_changed.connect(_refresh_upgrades)
	App.player_data.nutrients_changed.connect(_on_nutrients_changed)
	if node_level < App.mycelium_node_vms.size():
		bind(App.mycelium_node_vms[node_level])
	_refresh_upgrades()

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
	if App.upgrade_system.upgrades_changed.is_connected(_refresh_upgrades):
		App.upgrade_system.upgrades_changed.disconnect(_refresh_upgrades)
	if App.player_data.nutrients_changed.is_connected(_on_nutrients_changed):
		App.player_data.nutrients_changed.disconnect(_on_nutrients_changed)

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

func _refresh_all() -> void:
	label_buy_cost.text = _vm.buy_button_text
	panel_buy_node.set_enabled(_vm.can_buy_upgrade)
	owned_nodes.text =_vm.owned_node_text
	manual_nodes.text = _vm.manual_node_text
	label_node_income.text = _vm.production_text
	level_value.text = "%d" % [node_level + 1]
	label_node_name.text = _vm._mycelium_data._node.name
	label_node_desc.text = _vm.production_per_node_text
	_set_color()

func _on_nutrients_changed(_value: BigNumber) -> void:
	_refresh_upgrades()

func _refresh_upgrades() -> void:
	var us := App.upgrade_system
	var nutrients := App.player_data.nutrients
	var node_id := StringName(str(node_level))
	_refresh_upgrade_track(us, nutrients, _potency_id,
		label_potency_level, label_potency_gain_header, label_potency_accumulated, label_potency_cost,
		panel_potency, upgrade_button_potency,
		App.node_potency_bonus(node_id), App.node_potency_external_multiplier(node_id), "level")
	_refresh_upgrade_track(us, nutrients, _synergy_id,
		label_synergy_level, label_synergy_gain_header, label_synergy_accumulated, label_synergy_cost,
		panel_synergy, upgrade_button_synergy,
		App.node_synergy_bonus(node_id), App.node_synergy_external_multiplier(node_id), "manual node")
	var total := App.node_production_bonus(node_id).sub(BigNumber.from_value(1.0))
	label_yield.text = "+%s%%" % [total.scale(100.0)._to_string()]

func _refresh_upgrade_track(us: UpgradeSystem, nutrients: BigNumber, id: StringName,
		lvl_label: Label, header_label: Label, acc_label: Label, cost_label: Label,
		buy_panel, button: Button, bonus: BigNumber, external_mult: BigNumber, unit: String) -> void:
	var lvl := us.level(id)
	lvl_label.text = "Lv %d" % lvl
	header_label.text = "+%s%% / %s:" % [us.next_level_delta(id).mul(external_mult).scale(100.0)._to_string(), unit]
	acc_label.text = "now +%s%%" % [bonus.sub(BigNumber.from_value(1.0)).scale(100.0)._to_string()]
	cost_label.text = us.cost(id)._to_string() if us.has_def(id) else "--"
	var can_buy := us.can_buy(id, nutrients)
	button.disabled = not can_buy
	buy_panel.set_enabled(can_buy)

# --- View -> VM ---

func _on_upgrade_pressed() -> void:
	_vm.buy_upgrade()

func _on_buy_potency_pressed() -> void:
	App.upgrade_system.buy(_potency_id, App.player_data)

func _on_buy_synergy_pressed() -> void:
	App.upgrade_system.buy(_synergy_id, App.player_data)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_press_active = true
			_press_start = event.position
		elif _press_active:
			_press_active = false
			_toggle_synergy()
	elif event is InputEventMouseMotion and _press_active:
		# Android/iOS synthesize mouse motion from touch — a real scroll drag
		# starts as a press here too, so cancel the tap once it moves enough
		# to be a scroll rather than a tap.
		if event.position.distance_to(_press_start) > TAP_CANCEL_DISTANCE:
			_press_active = false

func _toggle_synergy() -> void:
	vbox_buy.visible = not vbox_buy.visible
	expansion_arrow.offset_transform_rotation = PI if vbox_buy.visible else 0.0 
	if App.biomes_data.is_unlocked(&"forest"):
		vbox_synergy.visible = vbox_buy.visible
	else:
		vbox_synergy.visible = false

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_update_shader()

func _update_shader() -> void:
	if material:
		material.set_shader_parameter("rect_size", size * get_global_transform().get_scale())

func _set_color() -> void:
	if material:
		material.set_shader_parameter(color_param, _vm._mycelium_data._node.color)
		level_icon._set_color(_vm._mycelium_data._node.color)
		panel_buy_node._set_color(_vm._mycelium_data._node.color)
		panel_potency._set_color(_vm._mycelium_data._node.color)
		panel_synergy._set_color(_vm._mycelium_data._node.color)
		var color_level_text = _vm._mycelium_data._node.level_font_color
		var color_main_text = Color.from_hsv(color_level_text.h, 0.7, 0.8)
		
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
