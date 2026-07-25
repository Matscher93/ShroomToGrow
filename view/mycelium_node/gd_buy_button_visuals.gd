@tool
extends PanelContainer

@export var ColorParam: String
@export var upgrade_button: Button
@export var deactivated_color: Color

var button_color : Color
var is_enabled : bool
var is_button_pressed : bool
func _ready():
	_update_shader()
	upgrade_button.button_down.connect(on_button_down)
	upgrade_button.button_up.connect(on_button_up)

func _notification(what):
	if what == NOTIFICATION_RESIZED:
		_update_shader()

func _update_shader():
	if material:
		material.set_shader_parameter("rect_size", size * get_global_transform().get_scale())
		if(is_enabled):
			material.set_shader_parameter(ColorParam, button_color)
			modulate = Color.WHITE
		else:
			material.set_shader_parameter(ColorParam, button_color.darkened(0.70))
			modulate = Color(0.3, 0.3, 0.3)

func _set_color(inColor : Color):
	button_color = inColor
	_update_shader()

func set_enabled(inEnabled : bool):
	is_enabled = inEnabled
	upgrade_button.disabled = not inEnabled
	_update_shader()
	
func on_button_down():
	is_button_pressed = true
	_update_shader()
	
func on_button_up():
	is_button_pressed = false
	_update_shader()
