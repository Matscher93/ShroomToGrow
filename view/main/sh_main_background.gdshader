shader_type canvas_item;

#include "res://shaders/sdf_lib.gdshaderinc"
#include "res://shaders/sdf_operations.gdshaderinc"
#include "res://shaders/sdf_spatial_manip.gdshaderinc"

uniform vec4 background_color : source_color;
uniform vec4 highlight_color : source_color;
uniform vec2 highlight_offset = vec2(0.0);
uniform float highlight_radius = 1.0;

// interleaved gradient noise — cheap, no texture needed
float ign(vec2 p) {
	return fract(52.9829189 * fract(dot(p, vec2(0.06711056, 0.00583715))));
}

void fragment() {
	// +/- half a quantization step of noise
	float dither = (ign(FRAGCOORD.xy) - 0.5) / 255.0;

	vec2 CenteredUVs = SpatialManipulation_CenterUVs(UV);
	float mask = SDF_Circle(CenteredUVs + highlight_offset, highlight_radius);
	vec4 col = mix(background_color, highlight_color, 1.0-mask);

	COLOR = col + vec4(vec3(dither), 0.0);
}
