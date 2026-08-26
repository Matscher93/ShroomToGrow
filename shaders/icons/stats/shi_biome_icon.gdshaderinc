#include "res://shaders/sdf_lib.gdshaderinc"
#include "res://shaders/sdf_operations.gdshaderinc"
#include "res://shaders/sdf_spatial_manip.gdshaderinc"

// A biome in general - "biomes open", "biome size", "deepest biome". The six
// authored per-biome shaders under shaders/icons/biomes/ each stand for one
// place; this stands for the idea, on the rows that count them rather than name
// one.
float biome_icon(vec2 UVspace, float icon_scale)
{
	vec2 p = SpatialManipulation_CenterUVs(UVspace)/icon_scale;
	// UV.y grows downwards; flipping once here lets every offset below read as
	// "up is positive", which is how the shape is described.
	p.y = -p.y;

	// A leaf as the lens between two circles set apart on x: the intersection
	// is tall and narrow with a point at each end, which no single primitive
	// here gives.
	float west = SDF_Circle(p - vec2(-0.62, 0.06), 1.10);
	float east = SDF_Circle(p - vec2(0.62, 0.06), 1.10);
	float blade = max(west, east);

	// Midrib cut out of the blade, and a stalk below it - without them the lens
	// is an eye, not a leaf.
	float midrib = SDF_LineSegment(p, vec2(0.0, -0.72), vec2(0.0, 0.82), 0.06);
	blade = Operation_SmoothSubtraction(blade, midrib, 0.0);

	float stalk = SDF_LineSegment(p, vec2(0.0, -0.88), vec2(0.0, -0.60), 0.08);

	float combined_sdf = min(blade, stalk);

	return Operation_HardShape(combined_sdf);
}
