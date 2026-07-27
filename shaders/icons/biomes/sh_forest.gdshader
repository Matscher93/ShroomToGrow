shader_type canvas_item;

#include "res://shaders/sdf_lib.gdshaderinc"
#include "res://shaders/sdf_operations.gdshaderinc"
#include "res://shaders/sdf_spatial_manip.gdshaderinc"
#include "res://shaders/oklab_lib.gdshaderinc"

uniform vec2 rect_size;
uniform vec4 box_color : source_color;
uniform vec3 trunk_color : source_color;
uniform vec3 leaves_color : source_color;
uniform vec2 box_extends = vec2(0.4);
uniform float corner_radius = 20;
uniform float highlight_radius = 1.0;
uniform vec2 higlight_offset = vec2(0.0);

vec4 icon(vec2 p)
{
	vec2 rotated_space = p*vec2(1.0, -1.0);
	float upper_triangle = SDF_Triangle_Equilateral(rotated_space+vec2(0.0,0.1)*rect_size, 0.4*rect_size.x);
	float lower_triangle = SDF_Triangle_Equilateral(rotated_space+vec2(0.0,-0.1)*rect_size, 0.45*rect_size.x);
	float leaves = Operation_SmoothUnion(upper_triangle, lower_triangle, 0.0);
	float trunk = SDF_Rectangle(p+vec2(0.0,-0.4)*rect_size, vec2(.1,.1)*rect_size);
	float tree = Operation_SmoothUnion(leaves, trunk, 0.0);
	vec3 color = mix(leaves_color, trunk_color, Operation_HardShape(trunk));
	return vec4(color, Operation_HardShape(tree));
}

void fragment() {
	vec2 p = SpatialManipulation_CenterUVs(UV) * rect_size; 
	
	float d = SDF_RoundedRectangle(
		p, 
		box_extends*rect_size, 
		vec4(corner_radius * 2.0)
	);
	
	float highlight_mask = SDF_Circle(SpatialManipulation_CenterUVs(UV)+higlight_offset, highlight_radius);
	vec3 mixed_color = mix(box_color.rgb * 0.5, box_color.rgb, 1.0-highlight_mask);
	float d_sharpened = Operation_HardShape(d);
	vec4 meadow_icon = icon(p);
	mixed_color = mix(mixed_color, meadow_icon.xyz, meadow_icon.a);
	
    COLOR = vec4(mixed_color, d_sharpened);
}
