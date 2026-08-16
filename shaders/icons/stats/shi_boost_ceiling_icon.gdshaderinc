#include "res://shaders/sdf_lib.gdshaderinc"
#include "res://shaders/sdf_operations.gdshaderinc"
#include "res://shaders/sdf_spatial_manip.gdshaderinc"

// Raising a crystal boost's ceiling. A bar with two chevrons climbing towards
// it: the bar is the cap, the chevrons are what the boon does to it. Kept apart
// from the crystal cluster, which stands for crystals themselves.
float boost_ceiling_icon(vec2 UVspace, float icon_scale)
{
	vec2 p = SpatialManipulation_CenterUVs(UVspace)/icon_scale;

	float bar = SDF_Rectangle(p - vec2(0.0, -0.74), vec2(0.62, 0.10));

	// Drawn as two legs each rather than a mirrored V, so the arms keep their
	// thickness at the apex instead of pinching.
	float upper_left = SDF_LineSegment(p, vec2(-0.46, -0.16), vec2(0.0, -0.50), 0.10);
	float upper_right = SDF_LineSegment(p, vec2(0.46, -0.16), vec2(0.0, -0.50), 0.10);
	float lower_left = SDF_LineSegment(p, vec2(-0.46, 0.42), vec2(0.0, 0.08), 0.10);
	float lower_right = SDF_LineSegment(p, vec2(0.46, 0.42), vec2(0.0, 0.08), 0.10);

	float chevrons = min(min(upper_left, upper_right), min(lower_left, lower_right));
	return Operation_HardShape(min(bar, chevrons));
}
