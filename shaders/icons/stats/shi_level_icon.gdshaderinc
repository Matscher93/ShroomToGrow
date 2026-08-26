#include "res://shaders/sdf_lib.gdshaderinc"
#include "res://shaders/sdf_operations.gdshaderinc"
#include "res://shaders/sdf_spatial_manip.gdshaderinc"

// Player level. Two stacked chevrons pointing up - the rank marking every game
// with a level uses, and the one shape here that means "how far up" rather than
// "how much of".
float level_icon(vec2 UVspace, float icon_scale)
{
	vec2 p = SpatialManipulation_CenterUVs(UVspace)/icon_scale;
	// UV.y grows downwards; flipping once here lets every offset below read as
	// "up is positive", which is how the shape is described.
	p.y = -p.y;

	// Drawn as segments rather than as outlined triangles: an outline thin
	// enough to leave two chevrons distinct is thinner than one row pixel.
	float upper_left = SDF_LineSegment(p, vec2(-0.62, 0.10), vec2(0.0, 0.62), 0.11);
	float upper_right = SDF_LineSegment(p, vec2(0.0, 0.62), vec2(0.62, 0.10), 0.11);
	float lower_left = SDF_LineSegment(p, vec2(-0.62, -0.56), vec2(0.0, -0.04), 0.11);
	float lower_right = SDF_LineSegment(p, vec2(0.0, -0.04), vec2(0.62, -0.56), 0.11);

	float combined_sdf = min(min(upper_left, upper_right), min(lower_left, lower_right));

	return Operation_HardShape(combined_sdf);
}
