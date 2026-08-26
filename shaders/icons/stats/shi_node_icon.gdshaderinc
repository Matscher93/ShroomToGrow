#include "res://shaders/sdf_lib.gdshaderinc"
#include "res://shaders/sdf_operations.gdshaderinc"
#include "res://shaders/sdf_spatial_manip.gdshaderinc"

// A mycelium node - the thing every "nodes grown" record counts.
//
// A hub with three filaments running off it, tipped so the arms end in
// something rather than trailing away. Hexagons and rings were both taken:
// glyph_icon is the hexagon and symbiosis_icon the rings, and at row size a
// second of either is indistinguishable from the first.
float node_icon(vec2 UVspace, float icon_scale)
{
	vec2 p = SpatialManipulation_CenterUVs(UVspace)/icon_scale;
	// UV.y grows downwards; flipping once here lets every offset below read as
	// "up is positive", which is how the shape is described.
	p.y = -p.y;

	float hub = SDF_Circle(p, 0.30);

	// Three arms at 90, 210 and 330 degrees: an even spread that is not
	// symmetric about either axis, so the shape cannot read as a plus or an X.
	float arm_up = SDF_LineSegment(p, vec2(0.0, 0.20), vec2(0.0, 0.74), 0.09);
	float arm_left = SDF_LineSegment(p, vec2(-0.17, -0.10), vec2(-0.64, -0.37), 0.09);
	float arm_right = SDF_LineSegment(p, vec2(0.17, -0.10), vec2(0.64, -0.37), 0.09);
	float arms = min(arm_up, min(arm_left, arm_right));

	float tip_up = SDF_Circle(p - vec2(0.0, 0.74), 0.16);
	float tip_left = SDF_Circle(p - vec2(-0.64, -0.37), 0.16);
	float tip_right = SDF_Circle(p - vec2(0.64, -0.37), 0.16);
	float tips = min(tip_up, min(tip_left, tip_right));

	float combined_sdf = min(hub, min(arms, tips));

	return Operation_HardShape(combined_sdf);
}
