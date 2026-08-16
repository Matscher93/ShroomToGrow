#include "res://shaders/sdf_lib.gdshaderinc"
#include "res://shaders/sdf_operations.gdshaderinc"
#include "res://shaders/sdf_spatial_manip.gdshaderinc"
#include "res://shaders/icons/currencies/shi_water_icon.gdshaderinc"

// How *often* the well pumps, as against how much it draws: the same droplet the
// water icon uses, shifted right to make room for motion streaks behind it. Built
// on the currency droplet rather than a second hand-drawn one so the two stay the
// same shape - the streaks are the whole difference, which is the point.
//
// The offset is halved because CenterUVs doubles what it is handed: a shift of
// `d` in UV space lands as `2 * d` in the centred space the droplet is drawn in.
float water_rate_icon(vec2 UVspace, float icon_scale)
{
	float drop = water_icon(UVspace - vec2(0.14, 0.0), icon_scale);

	vec2 p = SpatialManipulation_CenterUVs(UVspace)/icon_scale;
	// Three streaks of unequal length, the middle one longest, so they read as
	// speed lines rather than as a bracket.
	float streak_top = SDF_LineSegment(p, vec2(-0.86, -0.34), vec2(-0.52, -0.34), 0.07);
	float streak_mid = SDF_LineSegment(p, vec2(-0.94, 0.0), vec2(-0.46, 0.0), 0.07);
	float streak_low = SDF_LineSegment(p, vec2(-0.86, 0.34), vec2(-0.52, 0.34), 0.07);
	float streaks = Operation_HardShape(
		min(streak_mid, min(streak_top, streak_low)));

	// Both halves are already 0/1 masks, so the union is a max rather than an
	// SDF min - the droplet's distance field is gone by the time it gets here.
	return max(drop, streaks);
}
