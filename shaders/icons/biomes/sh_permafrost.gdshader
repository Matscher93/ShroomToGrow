shader_type canvas_item;

#include "res://shaders/sdf_lib.gdshaderinc"
#include "res://shaders/sdf_operations.gdshaderinc"
#include "res://shaders/sdf_spatial_manip.gdshaderinc"
#include "res://shaders/oklab_lib.gdshaderinc"

uniform vec2 rect_size;
uniform vec4 box_color : source_color;
uniform vec2 box_extends = vec2(0.4);
uniform float corner_radius = 20;
uniform float highlight_radius = 1.0;
uniform vec2 higlight_offset = vec2(0.0);

vec4 icon(vec2 p)
{
	float combined_line = 0.0;
	for(int i = 0; i < 3; i++)
	{
		vec2 rotated_space = SpatialManipulation_Rotate(p, float(i)*120.0);
		float line = SDF_LineSegment(rotated_space, vec2(.6,.0)*rect_size, vec2(-.6, .0)*rect_size, 3.0);
		combined_line = max(combined_line, Operation_HardShape(line));
	}
	
	vec3 color = vec3(1.0);
	 
	return vec4(color, combined_line);
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
