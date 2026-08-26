#include "res://shaders/sdf_lib.gdshaderinc"
#include "res://shaders/sdf_operations.gdshaderinc"
#include "res://shaders/sdf_spatial_manip.gdshaderinc"

// Elapsed time - how long a save has been played, how long a run has lasted.
//
// A calendar, and neither of the two shapes that would have been the first
// guess. tempo_icon is already the clock face and means something else entirely
// (how fast the game's own clock runs), and an hourglass comes out as the same
// pinched silhouette relic_icon's broken column has - the two sit four rows
// apart on the records tab, which is exactly where a near-miss costs the most.
float time_icon(vec2 UVspace, float icon_scale)
{
	vec2 p = SpatialManipulation_CenterUVs(UVspace)/icon_scale;
	// UV.y grows downwards; flipping once here lets every offset below read as
	// "up is positive", which is how the shape is described.
	p.y = -p.y;

	float page = SDF_RoundedRectangle(p - vec2(0.0, -0.12), vec2(0.74, 0.66), vec4(0.16));

	// Gap under the masthead, so the top band reads as a header rather than as
	// more page.
	float rule = SDF_Rectangle(p - vec2(0.0, 0.32), vec2(0.74, 0.06));
	page = Operation_SmoothSubtraction(page, rule, 0.0);

	// One day cut out of the grid below it - the mark that says a calendar is
	// being read rather than filled in.
	float day = SDF_RoundedRectangle(p - vec2(0.0, -0.28), vec2(0.19, 0.19), vec4(0.05));
	page = Operation_SmoothSubtraction(page, day, 0.0);

	// The two bindings above the page, mirrored so they cannot drift apart.
	vec2 m = SpatialManipulation_MirrorX(p);
	float binding = SDF_RoundedRectangle(m - vec2(0.36, 0.66), vec2(0.09, 0.19), vec4(0.06));

	float combined_sdf = min(page, binding);

	return Operation_HardShape(combined_sdf);
}
