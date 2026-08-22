#include "res://shaders/sdf_lib.gdshaderinc"
#include "res://shaders/sdf_operations.gdshaderinc"
#include "res://shaders/sdf_spatial_manip.gdshaderinc"

float relic_icon(vec2 UVspace, float scale)
{
	vec2 p = SpatialManipulation_CenterUVs(UVspace)/scale;

	// A broken column drum: a wide trapezoid base under a narrower shaft, with a
	// notch bitten out of one shoulder so it reads as ruined masonry rather than
	// as a plain plinth at pill size.
	float base = SDF_SymmetricTrapezoid(p - vec2(0.0, 0.52), 0.16, 0.62, 0.44);
	float shaft = SDF_Rectangle(p - vec2(0.0, -0.10), vec2(0.34, 0.48));
	float capital = SDF_SymmetricTrapezoid(p - vec2(0.0, -0.66), 0.14, 0.42, 0.58);

	float column = min(base, min(shaft, capital));

	// The bite. Off-centre on purpose - a symmetric notch reads as a keyhole.
	float chip = SDF_Circle(p - vec2(0.40, -0.30), 0.26);
	float combined_sdf = Operation_SmoothSubtraction(column, chip, 0.0);

	return Operation_HardShape(combined_sdf);
}
