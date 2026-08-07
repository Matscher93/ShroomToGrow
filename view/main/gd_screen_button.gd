@tool
extends "res://view/base_views/gd_base_shader_button.gd"
## VIEW: one bottom-bar nav tab. Adds a selected look to the shared shader-button
## base: the selected tab gets its own fill and full brightness, the rest sit
## greyed so the current screen is readable at a glance.

@export var _button: Button
@export var button_selected_color: Color

var is_selected: bool = false

func _ready() -> void:
	_update_shader()
	_bind_presses()

func _wrapped_button() -> Button:
	return _button

func _state_color() -> Color:
	return button_selected_color if is_selected else button_color

func _update_shader() -> void:
	super()
	modulate = Color.WHITE if is_selected else Color.GRAY

func set_selected(in_enabled: bool) -> void:
	is_selected = in_enabled
	_update_shader()
