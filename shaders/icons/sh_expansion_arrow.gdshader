shader_type canvas_item;

#include "res://shaders/sdf_lib.gdshaderinc"
#include "res://shaders/sdf_operations.gdshaderinc"
#include "res://shaders/sdf_spatial_manip.gdshaderinc"
#include "res://shaders/oklab_lib.gdshaderinc"
uniform float radius = 1.0;

void vertex() {
	// Called for every vertex the material is visible on.
}

void fragment() {
	vec2 UVs = SpatialManipulation_CenterUVs(UV)+vec2(0.0,0.0);
	float sdf = SDF_Triangle_Equilateral(UVs, radius);
	float sharpened = Operation_HardShape(sdf);
	
	COLOR = vec4(vec3(sharpened),sharpened*0.5);
}
