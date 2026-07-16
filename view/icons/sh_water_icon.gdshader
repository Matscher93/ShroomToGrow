shader_type canvas_item;

#include "res://shaders/icons/shi_water_icon.gdshaderinc"

uniform float icon_scale = 1.0;

void fragment() {
	COLOR = vec4(water_icon(UV, icon_scale));
}
