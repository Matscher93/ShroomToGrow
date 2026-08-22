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

	// A bell: a trapezoid skirt capped by a dome, with the crown and clapper
	// spelled out. At top-bar size the silhouette is what carries it, which is
	// why the skirt is wide and the flare shallow.
	float skirt = SDF_SymmetricTrapezoid(p - vec2(0.0, -0.08), 0.44, 0.30, 0.62);
	float dome = SDF_Circle(p - vec2(0.0, 0.34), 0.32);
	float body = Operation_SmoothUnion(skirt, dome, 0.10);

	// The lip the skirt sits on, wider than the skirt so it reads as a rim
	// rather than as more bell.
	float rim = SDF_RoundedRectangle(p - vec2(0.0, -0.56), vec2(0.72, 0.09), vec4(0.07));
	body = min(body, rim);

	// Crown above the dome and clapper below the rim - two small circles that
	// stop the shape reading as a plain dome.
	float crown = SDF_Circle(p - vec2(0.0, 0.72), 0.12);
	float clapper = SDF_Circle(p - vec2(0.0, -0.80), 0.14);

	float combined_sdf = min(min(body, crown), clapper);

	COLOR = vec4(icon_color.rgb, Operation_HardShape(combined_sdf));
}
