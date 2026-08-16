shader_type canvas_item;

#include "res://shaders/sdf_lib.gdshaderinc"
#include "res://shaders/sdf_operations.gdshaderinc"
#include "res://shaders/sdf_spatial_manip.gdshaderinc"
#include "res://shaders/oklab_lib.gdshaderinc"

uniform vec2 rect_size;
uniform vec4 box_color : source_color;
uniform vec2 box_extends = vec2(0.4);
uniform float corner_radius = 20;
uniform float highlight_radius = 1.0;
uniform vec2 higlight_offset = vec2(0.0);

vec4 icon(vec2 p)
{
	// Two stalactites hanging from the cavern roof over three ripple lines. The
	// gap between them is what reads as "underground water" at tab-icon size -
	// a drop alone would be any water at all, and an arch alone any cave.
	float spike_left = SDF_Triangle_Isoceles(
		p + vec2(0.13, 0.30) * rect_size, 0.06 * rect_size.x, -0.20 * rect_size.y);
	float spike_right = SDF_Triangle_Isoceles(
		p + vec2(-0.15, 0.34) * rect_size, 0.05 * rect_size.x, -0.15 * rect_size.y);
	float roof = SDF_Rectangle(
		p + vec2(0.0, 0.36) * rect_size, vec2(0.30, 0.05) * rect_size);
	float cave = Operation_SmoothUnion(roof, Operation_SmoothUnion(spike_left, spike_right, 0.0), 0.0);

	// Ripples widen downwards, so the surface reads as receding rather than as
	// three unrelated bars.
	float ripple_top = SDF_LineSegment(p,
		vec2(-0.14, -0.02) * rect_size, vec2(0.14, -0.02) * rect_size, 0.035 * rect_size.y);
	float ripple_mid = SDF_LineSegment(p,
		vec2(-0.22, 0.13) * rect_size, vec2(0.22, 0.13) * rect_size, 0.035 * rect_size.y);
	float ripple_low = SDF_LineSegment(p,
		vec2(-0.30, 0.28) * rect_size, vec2(0.30, 0.28) * rect_size, 0.035 * rect_size.y);
	float lake = Operation_SmoothUnion(ripple_top,
		Operation_SmoothUnion(ripple_mid, ripple_low, 0.0), 0.0);

	float shape = Operation_SmoothUnion(cave, lake, 0.0);
	return vec4(vec3(1.0), Operation_HardShape(shape));
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
	float d_sharpened = Operation_HardShape(d);
	vec4 lake_icon = icon(p);
	mixed_color = mix(mixed_color, lake_icon.xyz, lake_icon.a);

    COLOR = vec4(mixed_color, d_sharpened);
}
