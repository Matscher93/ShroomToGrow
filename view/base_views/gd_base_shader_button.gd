@tool
extends "res://view/base_views/gd_base_panel_container.gd"
## VIEW base: a shader-painted PanelContainer wrapped around a real Button.
##
## Three screens grew their own copy of this - the node card's buy button, the
## bottom-bar tab, the offline-income collect button - and every copy repeated the
## same press tracking, the same repaint on down/up, the same text setter. All
## that lives here now; a subclass only says which colour its current state
## paints, by overriding _state_color().
##
## The Button itself is not exported here: each scene already binds its own
## export name (`upgrade_button`, `_button`) by NodePath, and renaming those
## would mean rewriting six .tscn bindings for no gain. Subclasses hand it over
## by overriding _wrapped_button().

signal pressed()

@export var button_color: Color

var is_button_pressed: bool

## The Button this panel is painted around. Override in every subclass.
##
## Resolved per call rather than cached in _ready(), and that is load-bearing:
## callers configure a freshly instantiated button *before* putting it in the
## tree - GameScreens._rebuild_nav_buttons() sets the tab's text and selection
## and only then add_child()s it - so anything filled in _ready() is still empty
## when set_button_text() runs, and the caption silently keeps the scene's
## placeholder.
func _wrapped_button() -> Button:
	return null

## Call from the subclass's _ready(). Tolerates a null button so a half-wired
## scene fails visibly rather than at every press.
func _bind_presses() -> void:
	var button := _wrapped_button()
	if button == null:
		return
	button.button_down.connect(_on_button_down)
	button.button_up.connect(_on_button_up)

func set_button_text(button_text: String) -> void:
	var button := _wrapped_button()
	if button != null:
		button.text = button_text

## The colour the shader paints right now. Override to vary it by state - which
## is the only thing that actually differs between the subclasses.
func _state_color() -> Color:
	return button_color

func _update_shader() -> void:
	if material:
		material.set_shader_parameter("rect_size", size * get_global_transform().get_scale())
		material.set_shader_parameter(color_param, _state_color())

func set_shader_color(in_color: Color) -> void:
	button_color = in_color
	_update_shader()

func _on_button_down() -> void:
	is_button_pressed = true
	_update_shader()

func _on_button_up() -> void:
	is_button_pressed = false
	_update_shader()
	pressed.emit()
