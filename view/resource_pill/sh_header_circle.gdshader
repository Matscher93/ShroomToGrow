shader_type canvas_item;

#include "res://shaders/sdf_lib.gdshaderinc"
#include "res://shaders/sdf_operations.gdshaderinc"
#include "res://shaders/sdf_spatial_manip.gdshaderinc"

uniform vec2 rect_size;
uniform vec4 circle_color : source_color;
uniform float inner_radius = 0.5;
uniform float outer_radius = 0.8;

void vertex() {
}

void fragment() {
	vec2 p = SpatialManipulation_CenterUVs(UV) * rect_size; 
	float smaller_side = min(rect_size.x, rect_size.y);
	float inner_cirle = SDF_Circle(p, inner_radius * smaller_side);
	float sharp_shape = Operation_HardShape(inner_cirle);
	
	vec4 accent = clamp(2.0-vec4(1)*(-SDF_Circle(SpatialManipulation_CenterUVs(UV), 1.0)),1.0,2.0);
	vec4 highlight = pow(circle_color, 1.0/accent);
	float halo = SDF_Circle(p, outer_radius * smaller_side);
	float soft_shape = Operation_SoftShape(halo, 5);
    COLOR = vec4(mix(circle_color, highlight, sharp_shape).xyz, max(sharp_shape,soft_shape*0.3));
	
}