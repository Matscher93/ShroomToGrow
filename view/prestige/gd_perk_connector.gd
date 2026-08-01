@tool
class_name PerkConnector
extends Line2D
## VIEW: single parent->child edge in the mycelial web. Color and width per
## owned state are authored in sc_perk_connector.tscn so they can be restyled in
## the editor without touching PerkLines.
##
## The status colors are multiplied by the branch hue in sh_line.gdshader, so
## keep them near-neutral: they carry brightness, the branch carries hue.

@export var locked_color: Color = Color(0.35, 0.35, 0.35, 0.5)
@export var available_color: Color = Color(0.6, 0.6, 0.6, 0.75)
@export var owned_color: Color = Color(1.0, 1.0, 1.0, 0.85)
@export var locked_width: float = 1.5
@export var available_width: float = 1.5
@export var owned_width: float = 3.0
@export var locked_speed: float = 0.0
@export var available_speed: float = 1.0
@export var owned_speed: float = 1.0

func bind(from: Vector2, to: Vector2, status: String, zoom: float, branch_color: Color) -> void:
	points = PackedVector2Array([from, to])
	var speed := locked_speed
	match status:
		"owned":
			default_color = owned_color
			width = owned_width
			speed = owned_speed
		"available":
			default_color = available_color
			width = available_width
			speed = available_speed
		_:
			default_color = locked_color
			width = locked_width
	if material is ShaderMaterial:
		material.set_shader_parameter("speed", speed)
		material.set_shader_parameter("scale", zoom)
		material.set_shader_parameter("branch_color", branch_color)
		# The quad the shader rasterizes, in world units: segment length by
		# stroke width. UV is normalized over it, so the shader needs this to
		# turn its units back into pixels, e.g. for the glow falloff.
		material.set_shader_parameter("rect_size", Vector2(from.distance_to(to), width))
