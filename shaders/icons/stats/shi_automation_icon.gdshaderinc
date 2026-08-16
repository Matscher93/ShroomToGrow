#include "res://shaders/sdf_lib.gdshaderinc"
#include "res://shaders/sdf_operations.gdshaderinc"
#include "res://shaders/sdf_spatial_manip.gdshaderinc"

// How often an automation fires. A cog rather than a second clock face: tempo
// already owns the clock, and at row-icon size two clocks differing only in
// their hands are one icon as far as the player is concerned.
float automation_icon(vec2 UVspace, float icon_scale)
{
	vec2 p = SpatialManipulation_CenterUVs(UVspace)/icon_scale;

	// Blunt teeth: acuteness is a lerp from pointCount (blunt) towards 2 (a
	// spike), and a sharp eight-pointed star reads as a sun, not a gear.
	float teeth = SDF_NPointedStar(p, 0.82, 8.0, 0.35);
	// Filled body under the teeth, so the gaps between them stop at the rim
	// instead of cutting all the way to the centre.
	float body = SDF_Circle(p, 0.54);
	float gear = min(teeth, body);

	// The bore is what makes it a cog rather than a flower.
	float bore = SDF_Circle(p, 0.24);

	return Operation_HardShape(Operation_SmoothSubtraction(gear, bore, 0.0));
}
