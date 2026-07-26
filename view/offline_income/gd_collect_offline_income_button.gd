@tool
extends PanelContainer

@export var color_param: String
@export var _button: Button
@export var button_color: Color

signal pressed()

var is_selected : bool = false
var is_button_pressed : bool
func _ready() -> void:
	_update_shader()
	_button.button_down.connect(_on_button_down)
	_button.button_up.connect(_on_button_up)

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_update_shader()

func _update_shader() -> void:
	if material:
		material.set_shader_parameter("rect_size", size * get_global_transform().get_scale())
		material.set_shader_parameter(color_param, button_color)

func _set_color(in_color : Color) -> void:
	button_color = in_color
	_update_shader()

func set_selected(in_enabled : bool) -> void:
	is_selected = in_enabled
	_update_shader()

func set_button_text(button_text: String) -> void:
	_button.text = button_text

func _on_button_down() -> void:
	is_button_pressed = true
	_update_shader()

func _on_button_up() -> void:
	is_button_pressed = false
	_update_shader()
	pressed.emit()
