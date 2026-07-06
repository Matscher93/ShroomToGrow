@tool
class_name MyceliumNodePanel
extends PanelContainer

@export var ColorParam: String
@export var upgrade_button: Button
@export var auto_nodes: Label
@export var manual_nodes: Label
@export var level_value: Label
@export var level_header: Label
@export var label_node_name: Label
@export var label_node_desc: Label
@export var label_node_income: Label
@export var level_icon: ColorRect
@export var node_level: int = 0
var _vm: MyceliumNodeViewModel

func _ready() -> void:
	_update_shader()
	upgrade_button.pressed.connect(_on_upgrade_pressed)
	# Bind from the composition root (autoload). Views pull their VM,
	# which keeps scenes instantiable in isolation for testing too.
	if App.mycelium_node_vms[node_level]:
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
		MyceliumNodeViewModel.PROP_UPGRADE_TEXT:
			upgrade_button.text = _vm.upgrade_button_text
		MyceliumNodeViewModel.PROP_CAN_BUY:
			upgrade_button.disabled = not _vm.can_buy_upgrade
		MyceliumNodeViewModel.PROP_AUTO_NODE_TEXT:
			auto_nodes.text =_vm.auto_node_text
		MyceliumNodeViewModel.PROP_MANUAL_NODE_TEXT:
			manual_nodes.text = _vm.manual_node_text
		MyceliumNodeViewModel.PROP_PRODUCTION_TEXT:
			label_node_income.text = _vm.production_text

func _refresh_all() -> void:
	upgrade_button.text = _vm.upgrade_button_text
	upgrade_button.disabled = not _vm.can_buy_upgrade
	auto_nodes.text =_vm.auto_node_text
	manual_nodes.text = _vm.manual_node_text
	label_node_income.text = _vm.production_text
	level_value.text = "%d" % [node_level + 1]
	label_node_name.text = _vm._mycelium_data._node.name
	label_node_desc.text = _vm._mycelium_data._node.desc
	_set_color()

# --- View -> VM ---

func _on_upgrade_pressed() -> void:
	_vm.buy_upgrade()

func _notification(what):
	if what == NOTIFICATION_RESIZED:
		_update_shader()

func _update_shader():
	if material:
		material.set_shader_parameter("rect_size", size * get_global_transform().get_scale())

func _set_color():
	if material:
		var color_level_text = _vm._mycelium_data._node.level_font_color
		var color_main_text = Color.from_hsv(color_level_text.h, 0.7, 0.8)
		level_icon._set_color(_vm._mycelium_data._node.color)
		
		level_value.label_settings = level_value.label_settings.duplicate()
		level_header.label_settings = level_header.label_settings.duplicate()
		label_node_name.label_settings = label_node_name.label_settings.duplicate()
		auto_nodes.label_settings = auto_nodes.label_settings.duplicate()
		manual_nodes.label_settings = manual_nodes.label_settings.duplicate()
		
		level_value.label_settings.font_color = color_level_text
		level_header.label_settings.font_color = color_level_text
		label_node_name.label_settings.font_color = color_main_text
		auto_nodes.label_settings.font_color = color_main_text
		manual_nodes.label_settings.font_color = color_main_text
