#include "res://shaders/sdf_lib.gdshaderinc"
#include "res://shaders/sdf_operations.gdshaderinc"
#include "res://shaders/sdf_spatial_manip.gdshaderinc"

float biomass_icon(vec2 UVspace, float scale)
{
	vec2 p = SpatialManipulation_CenterUVs(UVspace)/scale;
	
	float hexagon_radius = 0.7;
	float circle_radius = 0.25;
	
	float sdf_1 = SDF_Hexagon(SpatialManipulation_Rotate(p,30), hexagon_radius);
	float sdf_2 = SDF_Circle(p, circle_radius);

	
	float combined_sdf = Operation_SmoothSubtraction(sdf_1, sdf_2, 0.0);
	
	float shape = Operation_HardShape(combined_sdf);
	
	return shape;
}