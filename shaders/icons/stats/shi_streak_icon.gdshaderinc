#include "res://shaders/sdf_lib.gdshaderinc"
#include "res://shaders/sdf_operations.gdshaderinc"
#include "res://shaders/sdf_spatial_manip.gdshaderinc"

// The daily streak. A flame, for the same reason every other game marks a streak
// with one: it is the shape that means "kept going".
//
// Deliberately lopsided. A symmetric teardrop is water_icon, which is three rows
// up the same records tab - the second lick and the scalloped base are what make
// this fire instead.
float streak_icon(vec2 UVspace, float icon_scale)
{
	vec2 p = SpatialManipulation_CenterUVs(UVspace)/icon_scale;
	// UV.y grows downwards; flipping once here lets every offset below read as
	// "up is positive", which is how the shape is described.
	p.y = -p.y;

	float base = SDF_Circle(p - vec2(-0.04, -0.34), 0.52);
	// Main tongue, leaning right of the base it rises from.
	float tongue = SDF_Triangle(p, vec2(-0.48, -0.24), vec2(0.20, -0.24), vec2(-0.06, 0.96));
	// A shorter second lick beside it, joined hard so the cleft between the two
	// survives - smoothed, the pair closes back up into the droplet water_icon
	// already owns.
	float lick = SDF_Triangle(p, vec2(0.16, -0.28), vec2(0.72, 0.00), vec2(0.54, 0.54));

	float flame = Operation_SmoothUnion(base, tongue, 0.16);
	flame = min(flame, lick);

	// Bitten out of the bottom left, so the flame sits on two feet rather than
	// on a round bottom.
	float notch = SDF_Circle(p - vec2(-0.62, -0.86), 0.36);

	float combined_sdf = Operation_SmoothSubtraction(flame, notch, 0.0);

	return Operation_HardShape(combined_sdf);
}
