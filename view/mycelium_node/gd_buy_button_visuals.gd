@tool
extends PanelContainer

@export var color_param: String
@export var upgrade_button: Button
@export var deactivated_color: Color

var button_color : Color
var is_enabled : bool
var is_button_pressed : bool
func _ready() -> void:
	_update_shader()
	upgrade_button.button_down.connect(_on_button_down)
	upgrade_button.button_up.connect(_on_button_up)

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_update_shader()

func _update_shader() -> void:
	if material:
		material.set_shader_parameter("rect_size", size * get_global_transform().get_scale())
		if(is_enabled):
			material.set_shader_parameter(color_param, button_color)
			modulate = Color.WHITE
		else:
			material.set_shader_parameter(color_param, button_color.darkened(0.70))
			modulate = Color(0.3, 0.3, 0.3)

func _set_color(in_color : Color) -> void:
	button_color = in_color
	_update_shader()

func set_enabled(in_enabled : bool) -> void:
	is_enabled = in_enabled
	upgrade_button.disabled = not in_enabled
	_update_shader()

func _on_button_down() -> void:
	is_button_pressed = true
	_update_shader()

func _on_button_up() -> void:
	is_button_pressed = false
	_update_shader()
