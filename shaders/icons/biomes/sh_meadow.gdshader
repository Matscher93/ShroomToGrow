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
	
	float flower_head_left = SDF_Circle(p+vec2(.25,0.2)*rect_size, 12.0);
	float flower_head_right = SDF_Circle(p+vec2(-.25,0.05)*rect_size, 10.0);
	float flower_head = Operation_SmoothUnion(flower_head_left, flower_head_right, 0.0);
	float flower_center_left = SDF_Circle(p+vec2(.25,0.2)*rect_size, 5.0);
	float flower_center_right = SDF_Circle(p+vec2(-.25,0.05)*rect_size, 4.0);
	float flower_center = Operation_SmoothUnion(flower_center_left, flower_center_right, 0.0);
	float flower_stem_left = SDF_LineSegment(p, vec2(-.25,.5)*rect_size, vec2(-.25,-.2)*rect_size, 2);
	float flower_stem_right = SDF_LineSegment(p, vec2(.25,.5)*rect_size, vec2(.25,-.0)*rect_size, 2);
	float flower_stem = Operation_SmoothUnion(flower_stem_left, flower_stem_right, 0.0);
	float combined_flower = Operation_SmoothUnion(flower_head, flower_stem, 0.0);
	
	vec3 color = mix(vec3(1.0), vec3(0.0), Operation_HardShape(flower_center));
	color = mix(color, vec3(0.0), Operation_HardShape(Operation_SmoothSubtraction(flower_stem, flower_head, 0.0)));
	return vec4(color, Operation_HardShape(combined_flower));
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
