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
	// Three standing columns of unequal height on a common plinth, with the
	// lintel broken away over the gap between the outer two. Unequal heights are
	// what reads as "ruin" at tab-icon size - three matched columns would be a
	// temple, and a temple is not what the player is walking into.
	float plinth = SDF_Rectangle(
		p + vec2(0.0, -0.30) * rect_size, vec2(0.34, 0.05) * rect_size);

	float column_left = SDF_Rectangle(
		p + vec2(0.22, -0.06) * rect_size, vec2(0.055, 0.22) * rect_size);
	float column_mid = SDF_Rectangle(
		p + vec2(0.0, -0.12) * rect_size, vec2(0.055, 0.16) * rect_size);
	float column_right = SDF_Rectangle(
		p + vec2(-0.22, -0.02) * rect_size, vec2(0.055, 0.26) * rect_size);

	float columns = Operation_SmoothUnion(column_left,
		Operation_SmoothUnion(column_mid, column_right, 0.0), 0.0);

	// The surviving stub of the lintel, sitting on the tallest column only. Left
	// short on purpose: a full span would close the silhouette back into an arch.
	float lintel = SDF_Rectangle(
		p + vec2(-0.16, 0.26) * rect_size, vec2(0.15, 0.045) * rect_size);

	float stones = Operation_SmoothUnion(plinth,
		Operation_SmoothUnion(columns, lintel, 0.0), 0.0);

	// A fallen block at the foot of the shortest column, which is what puts the
	// broken lintel somewhere rather than leaving it simply absent.
	float rubble = SDF_Rectangle(
		SpatialManipulation_Rotate(p + vec2(0.10, -0.22) * rect_size, 0.5),
		vec2(0.06, 0.04) * rect_size);

	float shape = Operation_SmoothUnion(stones, rubble, 0.0);
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
	vec4 ruins_icon = icon(p);
	mixed_color = mix(mixed_color, ruins_icon.xyz, ruins_icon.a);

    COLOR = vec4(mixed_color, d_sharpened);
}
