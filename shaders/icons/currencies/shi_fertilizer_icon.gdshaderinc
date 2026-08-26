#include "res://shaders/sdf_lib.gdshaderinc"
#include "res://shaders/sdf_operations.gdshaderinc"
#include "res://shaders/sdf_spatial_manip.gdshaderinc"

// The one currency with no icon of its own - fertilizer is spent by its own
// system rather than through CurrencyTypes, so it was never in the resource
// pill's id space and never got drawn.
//
// An open sack with granules spilling out of it. The sack alone is a bag of
// anything; the granules are what say it is feed rather than a purse.
float fertilizer_icon(vec2 UVspace, float scale)
{
	vec2 p = SpatialManipulation_CenterUVs(UVspace)/scale;
	// UV.y grows downwards; flipping once here lets every offset below read as
	// "up is positive", which is how the shape is described.
	p.y = -p.y;

	// Body and the tied neck above it, smoothly joined so the taper reads as
	// cloth gathering rather than as two stacked boxes.
	float body = SDF_RoundedRectangle(p - vec2(0.0, -0.32), vec2(0.56, 0.46), vec4(0.20));
	float neck = SDF_RoundedRectangle(p - vec2(0.0, 0.30), vec2(0.32, 0.16), vec4(0.08));
	float sack = Operation_SmoothUnion(body, neck, 0.10);

	// Three granules above the neck, spread wide enough to stay separate once
	// Operation_HardShape snaps them.
	float left = SDF_Circle(p - vec2(-0.34, 0.68), 0.13);
	float middle = SDF_Circle(p - vec2(0.02, 0.86), 0.13);
	float right = SDF_Circle(p - vec2(0.36, 0.66), 0.13);

	float combined_sdf = min(sack, min(left, min(middle, right)));

	return Operation_HardShape(combined_sdf);
}
