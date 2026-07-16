@tool
class_name MyceliumNodeChangePanel
extends PanelContainer

@export var ColorParam: String
@export var level_value: Label
@export var label_node_name: Label
@export var label_node_change: Label
@export var level_icon: ColorRect
@export var node_level: int = 0
var _vm: MyceliumNodeViewModel

func _ready() -> void:
	_update_shader()

func _on_upgrade_pressed() -> void:
	_vm.buy_upgrade()

func _notification(what):
	if what == NOTIFICATION_RESIZED:
		_update_shader()

func _update_shader():
	if material:
		material.set_shader_parameter("rect_size", size * get_global_transform().get_scale())
	
func set_data(node: MyceliumNode, i: int, node_change: BigNumber) -> void:
		material.set_shader_parameter(ColorParam, node.color)
		level_icon._set_color(node.color)
		var color_level_text = node.level_font_color
		var color_main_text = Color.from_hsv(color_level_text.h, 0.7, 0.8)
		
		level_value.label_settings = level_value.label_settings.duplicate()
		label_node_name.label_settings = label_node_name.label_settings.duplicate()
		label_node_change.label_settings = label_node_change.label_settings.duplicate()

		level_value.label_settings.font_color = color_level_text
		label_node_name.label_settings.font_color = color_main_text
		label_node_change.label_settings.font_color = color_main_text

		label_node_name.text = node.name
		level_value.text = "%d" % [i+1]
		label_node_change.text = node_change.to_display()
