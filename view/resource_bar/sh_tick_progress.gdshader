shader_type canvas_item;

#include "res://shaders/sdf_lib.gdshaderinc"
#include "res://shaders/sdf_operations.gdshaderinc"
#include "res://shaders/sdf_spatial_manip.gdshaderinc"

uniform vec2 rect_size;
uniform vec4 box_color : source_color;
uniform vec4 fill_color : source_color;
uniform vec2 box_extends = vec2(0.4);
uniform float corner_radius = 20;
uniform float border_thickness = 1.0;
uniform float additional_border_offset = 0.0;
uniform float background_alpha = 0.2;
uniform float border_alpha = 0.3;
uniform float tick_progress = 0.1;

void vertex() {
}

void fragment() {
	vec2 p = SpatialManipulation_CenterUVs(UV) * rect_size; 

	float progress = Operation_HardShape(1.0 - UV.x - 1.0 + tick_progress);
	
	float progress_shape = 
	Operation_HardShape(
		SDF_RoundedRectangle(
			p - vec2(rect_size.x*tick_progress-rect_size.x,0.0), 
			box_extends*rect_size*vec2(tick_progress,1.0)-border_thickness-additional_border_offset, 
			vec4(corner_radius * 2.0)
		)
	);

	float d = SDF_RoundedRectangle(
		p, 
		box_extends*rect_size-border_thickness-additional_border_offset, 
		vec4(corner_radius * 2.0)
	);
	
	float outline = Operation_Outline(d, border_thickness);
	
	float d_sharpened = Operation_HardShape(d);
	float outline_sharpened = Operation_HardShape(outline);
	
    vec4 background = vec4(box_color.rgb, mix(background_alpha*d_sharpened,border_alpha,outline_sharpened));

	COLOR = mix(background, fill_color, progress_shape);
}
