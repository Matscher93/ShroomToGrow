shader_type canvas_item;

#include "res://shaders/icons/shi_nutrient_icon.gdshaderinc"

uniform float icon_scale = 1.0;

void fragment() {
	COLOR = nutrient_icon(UV, icon_scale);
}
