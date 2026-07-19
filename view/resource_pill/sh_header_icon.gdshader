shader_type canvas_item;

#include "res://shaders/sdf_lib.gdshaderinc"
#include "res://shaders/sdf_operations.gdshaderinc"
#include "res://shaders/sdf_spatial_manip.gdshaderinc"

#include "res://shaders/icons/shi_nutrient_icon.gdshaderinc"
#include "res://shaders/icons/shi_water_icon.gdshaderinc"
#include "res://shaders/icons/shi_biomass_icon.gdshaderinc"

uniform vec2 rect_size;
uniform vec4 circle_color : source_color;
uniform float inner_radius = 0.5;
uniform float outer_radius = 0.8;
uniform float icon_scale = 1.0;
uniform int icon_id = 0;

float get_icon(vec2 space) {
	if (icon_id == 0) return nutrient_icon(space, icon_scale);
	if (icon_id == 1) return water_icon(space, icon_scale);
	if (icon_id == 2) return biomass_icon(space, icon_scale);
	return 0.0;
}

void fragment() {

	float sharp_shape = get_icon(UV);
	
    COLOR = vec4(circle_color.xyz, sharp_shape);
	
}