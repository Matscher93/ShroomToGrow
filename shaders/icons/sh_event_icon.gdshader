shader_type canvas_item;

#include "res://shaders/icons/stats/shi_event_icon.gdshaderinc"

uniform vec2 rect_size;
uniform vec4 icon_color : source_color;
uniform float icon_scale = 1.0;

// The bell itself lives in shi_event_icon.gdshaderinc, so the statistics
// overlay's "events resolved" row can dispatch to the same shape through
// sh_stat_icon.gdshader instead of a second copy of it.
void fragment() {
	COLOR = vec4(icon_color.rgb, event_icon(UV, icon_scale));
}
