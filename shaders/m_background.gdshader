shader_type canvas_item;

#include "res://shaders/sdf_lib.gdshaderinc"

uniform vec2 rect_size;
uniform vec4 circle_color : source_color;

void vertex() {
}

void fragment() {
	vec2 p = (UV - 0.5) * rect_size; // centered pixel coords

    COLOR = vec4(circle_color.rgb, circle_color.a);
}

//void light() {
//	// Called for every pixel for every light affecting the CanvasItem.
//	// Uncomment to replace the default light processing function with this one.
//}
