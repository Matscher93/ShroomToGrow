#include "res://shaders/sdf_lib.gdshaderinc"
#include "res://shaders/sdf_operations.gdshaderinc"
#include "res://shaders/sdf_spatial_manip.gdshaderinc"

float nutrient_icon(vec2 UVspace, float scale)
{
	vec2 p = SpatialManipulation_CenterUVs(UVspace)/scale;
	
	float circle_radius = 0.4;
	float center_offset = 0.5;
	
	float sdf_1 = SDF_Circle(p+vec2(0,3.0*center_offset/4.0), circle_radius);
	float sdf_2 = SDF_Circle(p+vec2(-center_offset*sqrt(3.0)/2.0, -3.0*center_offset/4.0), circle_radius);
	float sdf_3 = SDF_Circle(p+vec2(center_offset*sqrt(3.0)/2.0, -3.0*center_offset/4.0), circle_radius);
	
	float combined_sdf = Operation_SmoothUnion(sdf_3, Operation_SmoothUnion(sdf_1, sdf_2, 0.0), 0.0);
	
	float shape = Operation_HardShape(combined_sdf);
	
	return shape;
}