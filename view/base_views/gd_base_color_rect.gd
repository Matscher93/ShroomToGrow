@tool
extends ColorRect

@export var color_param: String
func _ready() -> void:
	_update_shader()

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_update_shader()

func _update_shader() -> void:
	if material:
		material.set_shader_parameter("rect_size", size * get_global_transform().get_scale())

func set_shader_color(in_color : Color) -> void:
	if material:
		material.set_shader_parameter(color_param, in_color)

## Swaps the icon's shader (e.g. per-biome shape) on this ColorRect's own
## ShaderMaterial. Assumes resource_local_to_scene = true so it can't bleed into
## other instances sharing the same base .tscn.
func set_icon_shader(in_shader: Shader) -> void:
	var shader_material := material as ShaderMaterial
	if shader_material and in_shader:
		shader_material.shader = in_shader
		_update_shader()
