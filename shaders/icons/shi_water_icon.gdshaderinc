#include "res://shaders/sdf_lib.gdshaderinc"
#include "res://shaders/sdf_operations.gdshaderinc"
#include "res://shaders/sdf_spatial_manip.gdshaderinc"

vec4 water_icon(vec2 UVspace, float icon_scale)
{
	vec2 p = SpatialManipulation_CenterUVs(UVspace)*icon_scale;
	float r1 = 0.01;
	float r2 = 0.5;
	float h = 1.0;
	
	float circle_radius = 0.12;
	
	float sdf_1 = SDF_UnevenCapsule(p-vec2(0.0,-(r2+h)/2.0), r1, r2, h);
	float sdf_2 = SDF_Circle(p+vec2(0.2,-0.3), circle_radius);
	
	float combined_sdf = Operation_SmoothSubtraction(sdf_1, sdf_2, 0.0);
	
	float shape = Operation_HardShape(combined_sdf);
	
	return vec4(1.0, 1.0, 1.0, shape);
}