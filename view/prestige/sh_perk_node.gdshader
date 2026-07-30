shader_type canvas_item;

#include "res://shaders/sdf_lib.gdshaderinc"
#include "res://shaders/sdf_operations.gdshaderinc"
#include "res://shaders/sdf_spatial_manip.gdshaderinc"
#include "res://shaders/oklab_lib.gdshaderinc"

uniform vec4 button_color : source_color = vec4(1.0);
uniform vec4 locked_color : source_color = vec4(0.16, 0.15, 0.19, 1.0);
uniform vec4 available_color : source_color = vec4(0.85, 0.75, 0.35, 1.0);
uniform vec4 unlocked_color : source_color = vec4(0.7, 0.55, 0.95, 1.0);
uniform vec4 selected_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float ring_thickness = 1.0;
uniform vec2 rect_size;
uniform float scale = 1.0;

uniform int status = 0; // 0=locked, 1=available, 2=unlocked, 3=selected

void fragment() {
	vec4 state_color = locked_color;
	if (status == 1) state_color = available_color;
	else if (status == 2) state_color = unlocked_color;
	else if (status == 3) state_color = selected_color;

	vec3 ring_color = vec3(1.0);
	if (status != 3) ring_color = button_color.xyz * state_color.xyz;
	vec2 p = SpatialManipulation_CenterUVs(UV)*rect_size;
	float circle_sdf = SDF_Circle(p, 0.8*rect_size.x);
	float inner_circle_sdf = SDF_Circle(p, 0.3*rect_size.x);
	float ring_sdf = Operation_Outline(circle_sdf, ring_thickness/scale);
	float glow_factor = 0.0;
	if (status > 0) glow_factor = 1.0;
	float glow_sdf = SDF_Circle(p, rect_size.x*(sin(TIME*2.0)+1.0)/10.0 + 0.6 * rect_size.x);
	
	
	
	float circle_shape = Operation_HardShape(circle_sdf);
	float inner_circle_shape = Operation_HardShape(inner_circle_sdf);
	float ring_shape = Operation_HardShape(ring_sdf);
	
	float shape = Operation_HardShape(Operation_SmoothUnion(inner_circle_sdf, ring_sdf*state_color.a, 0.0));
	
	vec3 mixed_color = vec3(1.0);
	mixed_color = mix(button_color.xyz * ring_sdf/rect_size.x, mixed_color, inner_circle_shape);
	mixed_color = mix(mixed_color, ring_color, ring_shape);
	mixed_color = mix(button_color.xyz, mixed_color, max(shape,circle_shape));
	
	COLOR = vec4(mixed_color, 
		max(max(max(circle_shape, shape)*state_color.w, 
		Operation_SoftShape(glow_sdf,10.0)*glow_factor - circle_shape), inner_circle_shape));
}
