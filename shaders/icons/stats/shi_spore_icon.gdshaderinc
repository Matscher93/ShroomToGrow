#include "res://shaders/sdf_lib.gdshaderinc"
#include "res://shaders/sdf_operations.gdshaderinc"
#include "res://shaders/sdf_spatial_manip.gdshaderinc"

// Sporations - a finished run, and the prestige milestone that records it.
//
// The mushroom itself, which nothing else in the game draws: biomass_icon is
// what a sporation pays out, and paying out is not the same event as trading
// the run in.
float spore_icon(vec2 UVspace, float icon_scale)
{
	vec2 p = SpatialManipulation_CenterUVs(UVspace)/icon_scale;
	// UV.y grows downwards; flipping once here lets every offset below read as
	// "up is positive", which is how the shape is described.
	p.y = -p.y;

	// Dome: a circle intersected with the half-plane above the gill line. A
	// SDF_CutCircle would do it in one call but takes its cut as a fraction of
	// the radius, which stops being a fixed line the moment the radius moves.
	float cap = max(SDF_Circle(p - vec2(0.0, -0.04), 0.80), -0.04 - p.y);

	// The gill bar under the cap is what stops the dome reading as a hill.
	float gills = SDF_RoundedRectangle(p - vec2(0.0, -0.15), vec2(0.66, 0.10), vec4(0.05));
	float stem = SDF_RoundedRectangle(p - vec2(0.0, -0.60), vec2(0.19, 0.40), vec4(0.09));

	float combined_sdf = min(cap, min(gills, stem));

	return Operation_HardShape(combined_sdf);
}
