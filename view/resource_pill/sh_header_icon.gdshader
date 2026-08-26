shader_type canvas_item;

#include "res://shaders/sdf_lib.gdshaderinc"
#include "res://shaders/sdf_operations.gdshaderinc"
#include "res://shaders/sdf_spatial_manip.gdshaderinc"

#include "res://shaders/icons/currencies/shi_nutrient_icon.gdshaderinc"
#include "res://shaders/icons/currencies/shi_water_icon.gdshaderinc"
#include "res://shaders/icons/currencies/shi_biomass_icon.gdshaderinc"
#include "res://shaders/icons/currencies/shi_crystal_icon.gdshaderinc"
#include "res://shaders/icons/currencies/shi_relic_icon.gdshaderinc"
#include "res://shaders/icons/currencies/shi_ichor_icon.gdshaderinc"
#include "res://shaders/icons/currencies/shi_glyph_icon.gdshaderinc"
#include "res://shaders/icons/currencies/shi_fertilizer_icon.gdshaderinc"

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
	if (icon_id == 3) return crystal_icon(space, icon_scale);
	if (icon_id == 4) return relic_icon(space, icon_scale);
	if (icon_id == 5) return ichor_icon(space, icon_scale);
	if (icon_id == 6) return glyph_icon(space, icon_scale);
	if (icon_id == 7) return fertilizer_icon(space, icon_scale);
	return 0.0;
}

void fragment() {

	float sharp_shape = get_icon(UV);
	
    COLOR = vec4(circle_color.xyz, sharp_shape);
	
}