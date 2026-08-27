@tool
class_name MyceliumNodeChangePanel
extends PanelContainer

@export var color_param: String
@export var level_value: Label
@export var label_node_name: Label
@export var label_node_change: Label
@export var level_icon: ColorRect
@export var node_level: int = 0

func _ready() -> void:
	_update_shader()

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_update_shader()

func _update_shader() -> void:
	if material:
		material.set_shader_parameter("rect_size", size * get_global_transform().get_scale())

## The tier this row is currently dressed as. Everything but the change figure -
## the three duplicated LabelSettings, the colours, the shader parameter, the
## name and the level number - depends only on this, and a row is built once and
## then refilled on every progress batch of the catch-up. Restyling it each time
## duplicated three Resources and rewrote four colours per row per batch for a
## result identical to the one already on screen.
var _styled_for: MyceliumNode = null
var _styled_level: int = -1

func set_data(node: MyceliumNode, i: int, node_change: BigNumber) -> void:
	if node != _styled_for or i != _styled_level:
		_styled_for = node
		_styled_level = i
		_apply_style(node, i)
	label_node_change.text = node_change.to_display()

func _apply_style(node: MyceliumNode, i: int) -> void:
	if material:
		material.set_shader_parameter(color_param, node.color)
	level_icon.set_shader_color(node.color)
	var color_level_text := node.level_font_color
	var color_main_text := Color.from_hsv(color_level_text.h, 0.7, 0.8)

	level_value.label_settings = level_value.label_settings.duplicate()
	label_node_name.label_settings = label_node_name.label_settings.duplicate()
	label_node_change.label_settings = label_node_change.label_settings.duplicate()

	level_value.label_settings.font_color = color_level_text
	label_node_name.label_settings.font_color = color_main_text
	label_node_change.label_settings.font_color = color_main_text

	label_node_name.text = node.name
	level_value.text = "%d" % [i+1]
