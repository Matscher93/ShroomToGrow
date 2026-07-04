@tool
extends ColorRect

@export var ColorParam: String
func _ready():
	_update_shader()

func _notification(what):
	if what == NOTIFICATION_RESIZED:
		_update_shader()

func _update_shader():
	if material:
		material.set_shader_parameter("rect_size", size * get_global_transform().get_scale())

func _set_color(inColor : Color):
	if material:
		material.set_shader_parameter(ColorParam, inColor)
