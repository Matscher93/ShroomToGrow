#include "res://shaders/sdf_lib.gdshaderinc"
#include "res://shaders/sdf_operations.gdshaderinc"
#include "res://shaders/sdf_spatial_manip.gdshaderinc"

// Symbiosis levels. Two interlocking rings: the upgrade track is what makes one
// node's output depend on another's, and two things bound together is the only
// reading a pair of linked rings has.
float symbiosis_icon(vec2 UVspace, float icon_scale)
{
	vec2 p = SpatialManipulation_CenterUVs(UVspace)/icon_scale;

	// Rings rather than discs, and overlapping rather than merely adjacent -
	// two separate discs are a colon at row size.
	float west = Operation_Outline(SDF_Circle(p - vec2(-0.30, 0.0), 0.54), 0.11);
	float east = Operation_Outline(SDF_Circle(p - vec2(0.30, 0.0), 0.54), 0.11);

	float combined_sdf = min(west, east);

	return Operation_HardShape(combined_sdf);
}
