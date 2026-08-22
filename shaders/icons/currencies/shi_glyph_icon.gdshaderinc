#include "res://shaders/sdf_lib.gdshaderinc"
#include "res://shaders/sdf_operations.gdshaderinc"
#include "res://shaders/sdf_spatial_manip.gdshaderinc"

float glyph_icon(vec2 UVspace, float scale)
{
	vec2 p = SpatialManipulation_CenterUVs(UVspace)/scale;

	// A carved sigil: a hexagonal tablet with a cross-stroke cut through it, so
	// the shape stays legible when the pill shrinks it and the strokes merge.
	float tablet = SDF_Hexagon(p, 0.78);
	float ring = Operation_Outline(tablet, 0.11);

	float bar_h = SDF_Rectangle(p, vec2(0.40, 0.07));
	float bar_v = SDF_Rectangle(p, vec2(0.07, 0.40));
	float mark = min(bar_h, bar_v);

	float combined_sdf = min(ring, mark);

	return Operation_HardShape(combined_sdf);
}
