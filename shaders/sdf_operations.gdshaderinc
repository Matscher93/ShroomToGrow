#include "res://shaders/sdf_constants.gdshaderinc"

float linearStep(const float min, const float max, const float x)
{
	return clamp((x - min) / (max - min), 0.0, 1.0);
}
 
float expStep(const float min, const float max, const float x)
{
	return exp(clamp((x - min) / (max - min), 0.0, 1.0))- 1.0;
}
 
float logStep(const float min, const float max, const float x, const float k)
{
	float t = clamp(((x - min) / (max - min)), 0.0, 1.0);
	return 1.0 - pow(1.0 - t, (1.0 / k));
}
 
float Operation_HardShape(const float sdf)
{
	float distanceChange = fwidth(sdf) * 0.5f;
	return smoothstep(distanceChange, -distanceChange, sdf);
}
 
float Operation_SoftShape(const float sdf, const float softness)
{
	return smoothstep(softness, -softness, sdf);
}

float Operation_HardShape_MaxDerivative(const float sdf)
{
	float maxderivative = max(abs(dFdx(sdf)), abs(dFdy(sdf)));
	return clamp((-sdf + maxderivative * 0.5) / maxderivative, 0.0, 1.0);
}
 
float Operation_HardShape_UVSpaceDerivative(const float sdf, const vec2 uv)
{
	float maxUVDerivative = max(abs(dFdx(uv.x)), abs(dFdy(uv.y)));
	return clamp((-sdf + maxUVDerivative  * 0.5) / maxUVDerivative , 0.0, 1.0);
}
 
float Operation_SmoothUnion(const float left, const float right, const float smoothingfactor)
{
	// would lead to a numerical collapse so we clamp
	float s = max(RADIANT_EPSILON,smoothingfactor * 0.1f);
    float h = max(s - abs(left-right), 0.f);
    float m = (0.25f * h *  h) / s;
    return min(left,  right) - m;
}
 
float Operation_SmoothSubtraction(const float left, const float right, const float smoothingfactor)
{
	return -Operation_SmoothUnion(-left, right, smoothingfactor);
}
 
float Operation_SmoothIntersection(const float left, const float right, const float smoothingfactor)
{
	return -Operation_SmoothUnion(-left, -right, smoothingfactor);
}

float Operation_Outline(const float sdf, float thickness)
{
	return abs(sdf) - thickness;
}