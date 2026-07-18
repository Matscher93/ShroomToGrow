@tool
class_name MyceliumSymbiosisPanel
extends PanelContainer

@export var ColorParam: String
@export var upgrade_button: Button
@export var upgrade_button_synergy: Button
@export var label_yield: Label
@export var level_value: Label
@export var level_header: Label
@export var label_node_name: Label
@export var label_node_desc: Label
@export var label_potency_label: Label
@export var label_potency_level: Label
@export var label_potency_accumulated: Label
@export var label_synergy_label: Label
@export var label_synergy_level: Label
@export var label_synergy_accumulated: Label
@export var label_potency_cost: Label
@export var panel_potency: PanelContainer
@export var label_synergy_cost: Label
@export var panel_synergy: PanelContainer
@export var level_icon: ColorRect
@export var node_level: int = 0
var _vm: MyceliumNodeViewModel
var _potency_id: StringName
var _synergy_id: StringName

func _ready() -> void:
	_update_shader()
	_potency_id = StringName("NodePotency%d" % node_level)
	_synergy_id = StringName("NodeSynergy%d" % node_level)
	upgrade_button.pressed.connect(_on_buy_potency_pressed)
	upgrade_button_synergy.pressed.connect(_on_buy_synergy_pressed)
	App.upgrade_system.upgrades_changed.connect(_refresh_upgrades)
	App.player_data.nutrients_changed.connect(_on_nutrients_changed)
	if App.mycelium_node_vms.size() > 0:
		if App.mycelium_node_vms[node_level]:
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
	pass


func _refresh_all() -> void:
	level_value.text = "%d" % [node_level + 1]
	label_node_name.text = _vm._mycelium_data._node.name
	label_node_desc.text = _vm._mycelium_data._node.desc
	_set_color()

func _on_nutrients_changed(_value: BigNumber) -> void:
	_refresh_upgrades()

func _refresh_upgrades() -> void:
	var us := App.upgrade_system
	var nutrients := App.player_data.nutrients
	_refresh_upgrade_track(us, nutrients, _potency_id,
		label_potency_level, label_potency_accumulated, label_potency_cost,
		panel_potency, upgrade_button)
	_refresh_upgrade_track(us, nutrients, _synergy_id,
		label_synergy_level, label_synergy_accumulated, label_synergy_cost,
		panel_synergy, upgrade_button_synergy)
	var total := us.combined_bonus([_potency_id, _synergy_id], App.resolve_context)
	label_yield.text = "+%d%%" % [int(round(total * 100.0))]

func _refresh_upgrade_track(us: UpgradeSystem, nutrients: BigNumber, id: StringName,
		lvl_label: Label, acc_label: Label, cost_label: Label,
		buy_panel, button: Button) -> void:
	var lvl := us.level(id)
	lvl_label.text = "Lv %d" % lvl
	acc_label.text = "now +%d%%" % [int(round(us.effect_amount(id, App.resolve_context) * 100.0))]
	cost_label.text = BigNumber.from_value(us.cost(id))._to_string() if us.has_def(id) else "--"
	var can_buy := us.can_buy(id, nutrients)
	button.disabled = not can_buy
	buy_panel.set_enabled(can_buy)

# --- View -> VM ---

func _on_buy_potency_pressed() -> void:
	App.upgrade_system.buy(_potency_id, App.player_data)

func _on_buy_synergy_pressed() -> void:
	App.upgrade_system.buy(_synergy_id, App.player_data)

func _notification(what):
	if what == NOTIFICATION_RESIZED:
		_update_shader()

func _update_shader():
	if material:
		material.set_shader_parameter("rect_size", size * get_global_transform().get_scale())

func _set_color():
	if material:
		material.set_shader_parameter(ColorParam, _vm._mycelium_data._node.color)
		level_icon._set_color(_vm._mycelium_data._node.color)
	
		var color_level_text = _vm._mycelium_data._node.level_font_color
		var color_main_text = Color.from_hsv(color_level_text.h, 0.7, 0.8)
		
		level_value.label_settings = level_value.label_settings.duplicate()
		level_header.label_settings = level_header.label_settings.duplicate()
		label_node_name.label_settings = label_node_name.label_settings.duplicate()

		
		level_value.label_settings.font_color = color_level_text
		level_header.label_settings.font_color = color_level_text
		label_node_name.label_settings.font_color = color_main_text
