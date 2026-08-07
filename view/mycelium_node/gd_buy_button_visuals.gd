@tool
extends "res://view/base_views/gd_base_shader_button.gd"
## VIEW: the buy-button panel on a node card, a biome's unlock row and its Biome
## Size row. Adds an enabled/disabled look to the shared shader-button base: the
## fill darkens and the whole panel dims, so an unaffordable purchase reads as
## unavailable rather than merely unlit.

@export var upgrade_button: Button

var is_enabled: bool

func _ready() -> void:
	_update_shader()
	_bind_presses()

func _wrapped_button() -> Button:
	return upgrade_button

func _state_color() -> Color:
	return button_color if is_enabled else button_color.darkened(0.70)

func _update_shader() -> void:
	super()
	modulate = Color.WHITE if is_enabled else Color(0.3, 0.3, 0.3)

func set_enabled(in_enabled: bool) -> void:
	is_enabled = in_enabled
	if upgrade_button != null:
		upgrade_button.disabled = not in_enabled
	_update_shader()
