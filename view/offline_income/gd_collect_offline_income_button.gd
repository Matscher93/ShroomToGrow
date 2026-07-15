@tool
extends PanelContainer

@export var ColorParam: String
@export var _button: Button
@export var button_color: Color

signal on_button_pressed()

var is_selected : bool = false
var is_button_pressed : bool
func _ready():
	_update_shader()
	_button.button_down.connect(_on_button_down)
	_button.button_up.connect(_on_button_up)

func _notification(what):
	if what == NOTIFICATION_RESIZED:
		_update_shader()

func _update_shader():
	if material:
		material.set_shader_parameter("rect_size", size * get_global_transform().get_scale())
		material.set_shader_parameter(ColorParam, button_color)

func _set_color(inColor : Color):
	button_color = inColor
	_update_shader()

func set_selected(inEnabled : bool):
	is_selected = inEnabled
	_update_shader()

func set_button_text(button_text: String) -> void:
	_button.text = button_text
		
func _on_button_down():
	is_button_pressed = true
	_update_shader()
	
func _on_button_up():
	is_button_pressed = false
	_update_shader()
	on_button_pressed.emit()
