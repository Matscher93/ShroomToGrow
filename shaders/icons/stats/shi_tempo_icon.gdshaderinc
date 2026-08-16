#include "res://shaders/sdf_lib.gdshaderinc"
#include "res://shaders/sdf_operations.gdshaderinc"
#include "res://shaders/sdf_spatial_manip.gdshaderinc"

// The only boon area with no currency of its own: how fast the clock runs.
// Nutrients, water, biomass and crystals all reuse their currency icon, so this
// is the one shape that had to be drawn.
float tempo_icon(vec2 UVspace, float icon_scale)
{
	vec2 p = SpatialManipulation_CenterUVs(UVspace)/icon_scale;

	// Ring rather than a filled disc: at row-icon size a solid circle reads as a
	// bullet point, and the hands inside are what make it a clock.
	float rim = Operation_Outline(SDF_Circle(p, 0.62), 0.09);

	// Pointing up and to the right, the one arrangement that stays legible when
	// the hands are only a few pixels long.
	float hand_hour = SDF_LineSegment(p, vec2(0.0, 0.0), vec2(0.0, -0.34), 0.07);
	float hand_minute = SDF_LineSegment(p, vec2(0.0, 0.0), vec2(0.28, 0.04), 0.07);

	float combined_sdf = Operation_SmoothUnion(rim,
		Operation_SmoothUnion(hand_hour, hand_minute, 0.0), 0.0);

	return Operation_HardShape(combined_sdf);
}
