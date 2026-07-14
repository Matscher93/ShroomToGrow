shader_type canvas_item;

#include "res://shaders/sdf_lib.gdshaderinc"
#include "res://shaders/sdf_operations.gdshaderinc"
#include "res://shaders/sdf_spatial_manip.gdshaderinc"

uniform vec2 rect_size;
uniform vec4 box_color : source_color;

float rand(float p) {
	return fract(cos(p*1217.89)*72134.568);
}

vec4 generate_sparks( vec2 fragCoord )
{
	const float ZOOM = 6.0;
	vec2 uv = vec2(fragCoord.x, 1.0-fragCoord.y);
	uv *= vec2(ZOOM, ZOOM*rect_size.y/rect_size.x);
	vec2 id = floor(uv);
	vec2 gv = fract(uv);
	
	float sdf = 1.0;
	for(int i = 0; i < int(ZOOM); i++)
	{
		vec2 spark_uv = SpatialManipulation_CenterUVs(vec2(uv.x-float(i), uv.y));
		spark_uv.y += -TIME*rand(id.x+1.1230) - rand(id.x)*ZOOM*rect_size.y/rect_size.x;
		spark_uv.y = mod(spark_uv.y, ZOOM*rect_size.y/rect_size.x)-1.0; 
		float size = 0.02+0.01*(sin((rand(id.y)+TIME*rand(id.y))/2.0)+1.0);
		sdf = Operation_SmoothUnion(sdf, SDF_Circle(spark_uv, size), 0.0);
	}
	return vec4(max(Operation_SoftShape(sdf, 0.15)*0.5, Operation_SoftShape(sdf, 0.025)));
}

void fragment() {
	vec4 sparks = generate_sparks(UV);
	COLOR = vec4(box_color.xyz, sparks.a * (UV.y-.5));
}