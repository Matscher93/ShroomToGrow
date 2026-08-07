shader_type canvas_item;

#include "res://shaders/sdf_lib.gdshaderinc"
#include "res://shaders/sdf_operations.gdshaderinc"
#include "res://shaders/sdf_spatial_manip.gdshaderinc"

uniform vec2 rect_size;
uniform vec4 icon_color : source_color;
uniform float icon_scale = 1.0;

void fragment() {
	vec2 p = SpatialManipulation_CenterUVs(UV) / icon_scale;
	// UV.y grows downwards; flipping once here lets every offset below read as
	// "up is positive", which is how the shape is described.
	p.y = -p.y;

	// A medal on a notched ribbon: the disc alone reads as a coin at top-bar
	// size, and the ribbon is what separates it from the currency icons sitting
	// a row below it.
	float ribbon = SDF_Rectangle(p - vec2(0.0, -0.45), vec2(0.40, 0.55));
	// Diamond subtracted from the ribbon's bottom edge, leaving the split tail.
	float notch = SDF_Rhombus(p - vec2(0.0, -1.00), vec2(0.34, 0.40));
	ribbon = Operation_SmoothSubtraction(ribbon, notch, 0.0);

	float disc = SDF_Circle(p - vec2(0.0, 0.36), 0.60);
	// Subtracted star, so the disc keeps a face instead of reading as a plain
	// coin once Operation_HardShape snaps the edges.
	float star = SDF_NPointedStar(p - vec2(0.0, 0.36), 0.34, 5.0, 0.45);
	disc = Operation_SmoothSubtraction(disc, star, 0.0);

	float combined_sdf = min(disc, ribbon);

	COLOR = vec4(icon_color.rgb, Operation_HardShape(combined_sdf));
}
