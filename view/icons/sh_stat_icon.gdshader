shader_type canvas_item;

// Dispatches an icon for the *area* an upgrade effect raises, e.g. the boon rows
// on a Well project card.
//
// Its own id space rather than the resource pill's: sh_header_icon.gdshader is
// indexed by CurrencyTypes ordinal (see gd_currency_types.gd, which says so),
// and a stat area is not a currency - tempo has no currency at all. The mapping
// from a stat name to an id lives in StatIcons, next to this file.

#include "res://shaders/icons/currencies/shi_nutrient_icon.gdshaderinc"
#include "res://shaders/icons/currencies/shi_water_icon.gdshaderinc"
#include "res://shaders/icons/currencies/shi_biomass_icon.gdshaderinc"
#include "res://shaders/icons/currencies/shi_crystal_icon.gdshaderinc"
#include "res://shaders/icons/stats/shi_tempo_icon.gdshaderinc"
#include "res://shaders/icons/stats/shi_water_rate_icon.gdshaderinc"
#include "res://shaders/icons/stats/shi_automation_icon.gdshaderinc"
#include "res://shaders/icons/stats/shi_boost_ceiling_icon.gdshaderinc"
#include "res://shaders/icons/stats/shi_boost_power_icon.gdshaderinc"
#include "res://shaders/icons/currencies/shi_relic_icon.gdshaderinc"
#include "res://shaders/icons/currencies/shi_ichor_icon.gdshaderinc"
#include "res://shaders/icons/currencies/shi_glyph_icon.gdshaderinc"
#include "res://shaders/icons/currencies/shi_fertilizer_icon.gdshaderinc"
#include "res://shaders/icons/stats/shi_time_icon.gdshaderinc"
#include "res://shaders/icons/stats/shi_node_icon.gdshaderinc"
#include "res://shaders/icons/stats/shi_biome_icon.gdshaderinc"
#include "res://shaders/icons/stats/shi_level_icon.gdshaderinc"
#include "res://shaders/icons/stats/shi_symbiosis_icon.gdshaderinc"
#include "res://shaders/icons/stats/shi_perk_icon.gdshaderinc"
#include "res://shaders/icons/stats/shi_streak_icon.gdshaderinc"
#include "res://shaders/icons/stats/shi_event_icon.gdshaderinc"
#include "res://shaders/icons/stats/shi_spore_icon.gdshaderinc"

uniform vec4 icon_color : source_color = vec4(1.0);
uniform float icon_scale = 1.0;
uniform int icon_id = 0;

float get_icon(vec2 space) {
	if (icon_id == 0) return nutrient_icon(space, icon_scale);
	if (icon_id == 1) return water_icon(space, icon_scale);
	if (icon_id == 2) return biomass_icon(space, icon_scale);
	if (icon_id == 3) return crystal_icon(space, icon_scale);
	if (icon_id == 4) return tempo_icon(space, icon_scale);
	if (icon_id == 5) return water_rate_icon(space, icon_scale);
	if (icon_id == 6) return automation_icon(space, icon_scale);
	if (icon_id == 7) return boost_ceiling_icon(space, icon_scale);
	if (icon_id == 8) return boost_power_icon(space, icon_scale);
	// 9 and up are the statistics overlay's row icons: the three currencies the
	// boon rows never needed, and the shapes for the things a records row counts
	// that are not currencies at all.
	if (icon_id == 9) return relic_icon(space, icon_scale);
	if (icon_id == 10) return ichor_icon(space, icon_scale);
	if (icon_id == 11) return glyph_icon(space, icon_scale);
	if (icon_id == 12) return fertilizer_icon(space, icon_scale);
	if (icon_id == 13) return time_icon(space, icon_scale);
	if (icon_id == 14) return node_icon(space, icon_scale);
	if (icon_id == 15) return biome_icon(space, icon_scale);
	if (icon_id == 16) return level_icon(space, icon_scale);
	if (icon_id == 17) return symbiosis_icon(space, icon_scale);
	if (icon_id == 18) return perk_icon(space, icon_scale);
	if (icon_id == 19) return streak_icon(space, icon_scale);
	if (icon_id == 20) return event_icon(space, icon_scale);
	if (icon_id == 21) return spore_icon(space, icon_scale);
	return 0.0;
}

void fragment() {
	COLOR = vec4(icon_color.rgb, icon_color.a * get_icon(UV));
}
