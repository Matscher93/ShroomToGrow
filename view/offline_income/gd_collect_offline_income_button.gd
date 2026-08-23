@tool
extends "res://view/base_views/gd_base_shader_button.gd"
## VIEW: the wide pill button - offline income's collect action and the prestige
## screen's sporate action. Adds a disabled look to the shared shader-button
## base, driven off the wrapped Button's own `disabled` rather than a flag of its
## own, so a caller only has to disable the Button.

## every enabled button state gets the same font color - the pill's own shader
## background already carries the state feedback, so hover/pressed text tinting only
## muddies it. disabled is the exception, it gets disabled_text_color.
const _FONT_COLOR_OVERRIDES: Array[StringName] = [
	&"font_color",
	&"font_focus_color",
	&"font_pressed_color",
	&"font_hover_color",
	&"font_hover_pressed_color",
]

@export var _button: Button
@export var disabled_color: Color = Color(0.35, 0.35, 0.35, 1):
	set(value):
		disabled_color = value
		_update_shader()
@export var text_color: Color = Color.BLACK:
	set(value):
		text_color = value
		_update_text_color()
@export var disabled_text_color: Color = Color(0.55, 0.55, 0.55, 1):
	set(value):
		disabled_text_color = value
		_update_text_color()

var is_selected: bool = false

func _ready() -> void:
	_update_shader()
	_update_text_color()
	_bind_presses()

func _wrapped_button() -> Button:
	return _button

func _state_color() -> Color:
	return disabled_color if _is_disabled() else button_color

func _is_disabled() -> bool:
	return _button != null and _button.disabled

func _update_text_color() -> void:
	if _button == null:
		return
	for override in _FONT_COLOR_OVERRIDES:
		_button.add_theme_color_override(override, text_color)
	_button.add_theme_color_override(&"font_disabled_color", disabled_text_color)

func set_text_color(in_color: Color) -> void:
	text_color = in_color

func set_selected(in_enabled: bool) -> void:
	is_selected = in_enabled
	_update_shader()

func set_disabled(value: bool) -> void:
	if _button != null:
		_button.disabled = value
	_update_shader()
