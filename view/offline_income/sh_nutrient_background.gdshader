shader_type canvas_item;

#include "res://shaders/sdf_lib.gdshaderinc"
#include "res://shaders/sdf_operations.gdshaderinc"
#include "res://shaders/sdf_spatial_manip.gdshaderinc"
#include "res://shaders/oklab_lib.gdshaderinc"

#include "res://shaders/icons/shi_nutrient_icon.gdshaderinc"
#include "res://shaders/icons/shi_water_icon.gdshaderinc"
#include "res://shaders/icons/shi_biomass_icon.gdshaderinc"

uniform vec2 rect_size;
uniform vec4 box_color : source_color;
uniform vec2 box_extends = vec2(0.4);
uniform float corner_radius = 20;
uniform float highlight_radius = 1.0;
uniform vec2 higlight_offset = vec2(0.0);
uniform int icon_id;
uniform float icon_scale = 1.0;

void vertex() {
}

float get_icon(vec2 space) {
	if (icon_id == 0) return nutrient_icon(space, icon_scale);
	if (icon_id == 1) return water_icon(space, icon_scale);
	if (icon_id == 2) return biomass_icon(space, icon_scale);
	return 0.0;
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
	mixed_color = mix(mixed_color, vec3(0.0), get_icon(UV));
	float d_sharpened = Operation_HardShape(d);
	
    COLOR = vec4(mixed_color, d_sharpened);
}
