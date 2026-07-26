@tool
extends PanelContainer

@export var color_param: String
func _ready() -> void:
	_update_shader()

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_update_shader()

func _update_shader() -> void:
	if material:
		material.set_shader_parameter("rect_size", size * get_global_transform().get_scale())

func _set_color(in_color : Color) -> void:
	if material:
		material.set_shader_parameter(color_param, in_color)
