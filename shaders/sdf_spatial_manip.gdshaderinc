#include "res://shaders/sdf_constants.gdshaderinc"
vec2 SpatialManipulation_CenterUVs(vec2 position)
{
	vec2 p = position;
	return (p - 0.5) * 2.0;
}

vec2 SpatialManipulation_MirrorX(vec2 position)
{
	vec2 p = position;
	p.x = abs(p.x);
	return p;
}
 
vec2 SpatialManipulation_MirrorY(vec2 position)
{
	vec2 p = position;
    p.y = abs(p.y);
    return p;
}
 
vec2 SpatialManipulation_MirrorXY(vec2 position)
{
    return abs(position);
}
 
vec2 SpatialManipulation_RepeatInfinite(vec2 position, const vec2 repUnits)
{
	return position - repUnits * round(position / repUnits);
}
 
vec2 SpatialManipulation_RepeatLimited(vec2 position, const vec2 repUnits, const vec2 repetitions)
{
	return position - repUnits * clamp(round(position / repUnits), -repetitions, repetitions);
}
 
vec2 SpatialManipulation_Rotate(vec2 position, const float angle)
{
	const float aRadians = angle * RADIANT_DEG_TO_RAD;
	const float c = cos(aRadians);
	const float s = sin(aRadians);
	const mat2 rm = mat2(vec2(c, -s), vec2(s, c));
	return rm * position;
}