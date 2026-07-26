shader_type canvas_item;

#include "res://shaders/sdf_lib.gdshaderinc"
#include "res://shaders/sdf_operations.gdshaderinc"
#include "res://shaders/sdf_spatial_manip.gdshaderinc"
#include "res://shaders/oklab_lib.gdshaderinc"

uniform float radius = 0.5;
uniform float radius_glow = 1.0;
uniform float border_thickness = 0.05;

uniform vec3 notification_color : source_color;
uniform vec3 ring_color : source_color;

void vertex() {
	// Called for every vertex the material is visible on.
}

void fragment() {
	vec2 Coords = SpatialManipulation_CenterUVs(UV);
	float sdf_circle = SDF_Circle(Coords, radius);
	float sdf_glow = -1.0 * SDF_Circle(Coords, radius_glow);
	float sdf_ring = Operation_Outline(sdf_circle, border_thickness);
	float shape_circle = Operation_HardShape(sdf_circle);
	float shape_ring = Operation_HardShape(sdf_ring);
	float opacity = max(max(sdf_glow, shape_circle), shape_ring);	
	
	COLOR = vec4(mix(notification_color, ring_color, shape_ring), opacity);
}
