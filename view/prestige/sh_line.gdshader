shader_type canvas_item;

#include "res://shaders/sdf_lib.gdshaderinc"
#include "res://shaders/sdf_operations.gdshaderinc"
#include "res://shaders/sdf_spatial_manip.gdshaderinc"
#include "res://shaders/oklab_lib.gdshaderinc"

uniform float speed = 1.0;
uniform float scale = 1.0;
uniform vec4 branch_color : source_color = vec4(1.0);
uniform float glow_thickness;
uniform float glow_falloff;
uniform float glow_strength;
uniform vec2 rect_size;

// d: signed distance, thickness: half-width of the solid core
float sdf_core(float d, float thickness) {
    float aa = fwidth(d) * 0.5;
    return 1.0 - smoothstep(thickness - aa, thickness + aa, d);
}

// falloff: larger = tighter glow
float sdf_glow(float d, float thickness, float falloff) {
    return exp(-max(d - thickness, 0.0) * falloff);
}

float ign(vec2 frag_coord) {
    return fract(52.9829189 * fract(dot(frag_coord, vec2(0.06711056, 0.00583715))));
}

vec4 dither(vec4 color, vec2 frag_coord, float amount) {
    float n = (ign(frag_coord) - 0.5) * amount / 255.0;
    return vec4(color.rgb + n, color.a + n);
}

void fragment() {
	float x = fract((UV.x)*scale*2.0 + (-TIME * speed*scale));
	float y = (UV.y-.5)*scale*2.0;

	float sdf = SDF_LineSegment(vec2(x,y), vec2(.25,0.0), vec2(.75,0.0), 0.075);
	float core = sdf_core(sdf, glow_thickness);
    float glow = sdf_glow(sdf, glow_thickness, glow_falloff / max(rect_size.y*scale, 1.0)) * glow_strength/scale;
	float n = (ign(FRAGCOORD.xy) - 0.5) / 255.0;
	glow += n;
	
	vec4 in_color = COLOR;
	float a = clamp(glow + core, 0.0, 1.0);
	COLOR = vec4(in_color.xyz * branch_color.xyz, a);
}
