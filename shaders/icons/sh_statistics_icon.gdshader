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

	// Three bars climbing left to right, all standing on the same baseline. The
	// climb is what makes it a chart rather than three stripes - at top-bar size
	// equal bars read as a menu glyph.
	float base = -0.75;
	float short_bar = SDF_Rectangle(p - vec2(-0.52, base + 0.30), vec2(0.20, 0.30));
	float mid_bar = SDF_Rectangle(p - vec2(0.0, base + 0.58), vec2(0.20, 0.58));
	float tall_bar = SDF_Rectangle(p - vec2(0.52, base + 0.86), vec2(0.20, 0.86));

	float combined_sdf = min(short_bar, min(mid_bar, tall_bar));

	COLOR = vec4(icon_color.rgb, Operation_HardShape(combined_sdf));
}
