#include "res://shaders/sdf_lib.gdshaderinc"
#include "res://shaders/sdf_operations.gdshaderinc"
#include "res://shaders/sdf_spatial_manip.gdshaderinc"

// Perk levels. A sharp five-pointed star - a talent, the way every skill tree
// marks one.
//
// It was a branch first, which is what the perk screen actually looks like, and
// that was the problem: node_icon is a hub with three filaments, and at row size
// two branching shapes two lines apart on the records tab are one icon.
// automation_icon is the only other star here and is a blunt eight-toothed gear
// around a bore, which reads as machinery rather than as a point.
float perk_icon(vec2 UVspace, float icon_scale)
{
	vec2 p = SpatialManipulation_CenterUVs(UVspace)/icon_scale;
	// UV.y grows downwards; flipping once puts the single point at the top,
	// which is the orientation a star is read in.
	p.y = -p.y;

	float combined_sdf = SDF_NPointedStar(p, 0.92, 5.0, 0.42);

	return Operation_HardShape(combined_sdf);
}
