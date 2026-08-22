#include "res://shaders/sdf_lib.gdshaderinc"
#include "res://shaders/sdf_operations.gdshaderinc"
#include "res://shaders/sdf_spatial_manip.gdshaderinc"

float ichor_icon(vec2 UVspace, float scale)
{
	vec2 p = SpatialManipulation_CenterUVs(UVspace)/scale;

	// A falling droplet with a second, smaller bead trailing it - close enough to
	// the water glyph to read as a fluid, different enough not to be mistaken for
	// it in a pill row that can show both.
	float head = SDF_UnevenCapsule(p - vec2(0.0, -0.18), 0.06, 0.40, 0.62);
	float bead = SDF_Circle(p - vec2(0.0, 0.66), 0.17);

	float drop = Operation_SmoothUnion(head, bead, 0.06);

	// Highlight bitten out of the shoulder, the same trick the water icon uses.
	float glint = SDF_Circle(p - vec2(-0.16, 0.18), 0.11);
	float combined_sdf = Operation_SmoothSubtraction(drop, glint, 0.0);

	return Operation_HardShape(combined_sdf);
}
