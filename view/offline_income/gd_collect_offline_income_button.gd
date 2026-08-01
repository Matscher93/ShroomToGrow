@tool
extends PanelContainer

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

@export var color_param: String
@export var _button: Button
@export var button_color: Color
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

signal pressed()

var is_selected : bool = false
var is_button_pressed : bool
func _ready() -> void:
	_update_shader()
	_update_text_color()
	_button.button_down.connect(_on_button_down)
	_button.button_up.connect(_on_button_up)

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_update_shader()

func _update_shader() -> void:
	if material:
		material.set_shader_parameter("rect_size", size * get_global_transform().get_scale())
		material.set_shader_parameter(color_param, disabled_color if _is_disabled() else button_color)

func _is_disabled() -> bool:
	return _button != null and _button.disabled

func _update_text_color() -> void:
	if _button == null:
		return
	for override in _FONT_COLOR_OVERRIDES:
		_button.add_theme_color_override(override, text_color)
	_button.add_theme_color_override(&"font_disabled_color", disabled_text_color)

func set_text_color(in_color : Color) -> void:
	text_color = in_color

func set_shader_color(in_color : Color) -> void:
	button_color = in_color
	_update_shader()

func set_selected(in_enabled : bool) -> void:
	is_selected = in_enabled
	_update_shader()

func set_button_text(button_text: String) -> void:
	_button.text = button_text

func set_disabled(value: bool) -> void:
	_button.disabled = value
	_update_shader()

func _on_button_down() -> void:
	is_button_pressed = true
	_update_shader()

func _on_button_up() -> void:
	is_button_pressed = false
	_update_shader()
	pressed.emit()
