@tool
extends NinePatchRect

func _ready():
	_update_shader()

func _notification(what):
	if what == NOTIFICATION_RESIZED:
		_update_shader()

func _update_shader():
	if material:
		material.set_shader_parameter("rect_size", size)
