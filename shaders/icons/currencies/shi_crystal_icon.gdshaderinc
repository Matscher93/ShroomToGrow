#include "res://shaders/sdf_lib.gdshaderinc"
#include "res://shaders/sdf_operations.gdshaderinc"
#include "res://shaders/sdf_spatial_manip.gdshaderinc"

float crystal_icon(vec2 UVspace, float scale)
{
	vec2 p = SpatialManipulation_CenterUVs(UVspace)/scale;

	// A tall centre gem flanked by two smaller shards, so the icon reads as a
	// crystal cluster rather than a plain diamond at pill size.
	float centre = SDF_Rhombus(p, vec2(0.34, 0.72));
	float left = SDF_Rhombus(p - vec2(-0.42, 0.18), vec2(0.20, 0.40));
	float right = SDF_Rhombus(p - vec2(0.42, 0.18), vec2(0.20, 0.40));

	float cluster = min(centre, min(left, right));

	// Subtracted facet line down the centre gem, thin enough to stay visible
	// once Operation_HardShape snaps the edges.
	float facet = SDF_Rectangle(p - vec2(0.0, -0.05), vec2(0.035, 0.42));
	float combined_sdf = Operation_SmoothSubtraction(cluster, facet, 0.0);

	return Operation_HardShape(combined_sdf);
}
