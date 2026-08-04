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
	// Three gems of falling height, offset sideways, reading as a cave cluster.
	float centre = SDF_Rhombus(p + vec2(0.0, -0.05) * rect_size, vec2(0.13, 0.30) * rect_size);
	float left = SDF_Rhombus(p + vec2(0.24, -0.14) * rect_size, vec2(0.09, 0.19) * rect_size);
	float right = SDF_Rhombus(p + vec2(-0.26, -0.16) * rect_size, vec2(0.08, 0.16) * rect_size);

	float cluster = Operation_SmoothUnion(centre, Operation_SmoothUnion(left, right, 0.0), 0.0);

	// Facet line down the centre gem, drawn dark on the otherwise white icon so
	// the silhouette still reads as faceted at tab-icon size.
	float facet = SDF_LineSegment(p, vec2(0.0, -0.30) * rect_size, vec2(0.0, 0.22) * rect_size, 2.0);

	vec3 color = mix(vec3(1.0), vec3(0.0), Operation_HardShape(facet));
	return vec4(color, Operation_HardShape(cluster));
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
	vec4 caves_icon = icon(p);
	mixed_color = mix(mixed_color, caves_icon.xyz, caves_icon.a);

    COLOR = vec4(mixed_color, d_sharpened);
}
