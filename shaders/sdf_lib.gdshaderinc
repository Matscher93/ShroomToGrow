#include "res://shaders/sdf_constants.gdshaderinc"

float dot2(vec2 v)
{
	return dot(v, v);
}
 
vec2 sincos2(float x)
{
	return vec2(sin(x), cos(x));
}
 
vec2 cossin2(float x)
{
	return vec2(cos(x),sin(x));
}
 
vec2 mod21(vec2 x, float y)
{
	vec2 yy = vec2(y, y);
	return x - yy * floor(x / yy);
}
 
 
float SDF_Circle(
	const vec2 position,
	const float radius)
{
	return length(position) - radius;
}
 
float SDF_Rectangle(
	const vec2 position,
	const vec2 extents)
{
	vec2 inOrOut = abs(position) - extents;
	return length(max(inOrOut, 0.f)) + min(max(inOrOut.x,inOrOut.y), 0.f);
}
 
float SDF_RoundedRectangle(
	const vec2 position,
	const vec2 extents,
	const vec4 cornerRadii)
{
	vec4 radii = cornerRadii;
	radii.xy = (position.x > 0.0) ? radii.xy : radii.zw;
    float finalRadius  = (position.y > 0.0) ? radii.x  : radii.y;
    vec2 q = abs(position) - extents + finalRadius;
    return min(max(q.x,q.y),0.0) + length(max(q,0.0)) - finalRadius;
}
 
float SDF_ChamferedRectangle(
	const vec2 position,
	const vec2 extents,
	const float chamfer)
{
	vec2 pos = position;
    pos  = abs(pos ) - extents;
 
    pos  = (pos.y > pos.x) ? pos.yx : pos.xy;
    pos.y += chamfer;
    
    const float k = 1.0 - RADIANT_SQRT2;
    if( pos.y < 0.0 && pos.y + pos.x * k < 0.0 )
        return pos.x;
    
    if( pos.x < pos.y )
        return (pos.x + pos.y) * RADIANT_SQRTHALF;    
    
    return length(pos);
}
 
float SDF_LineSegment(
	const vec2 position, 
	const vec2 point1, 
	const vec2 point2, 
	const float thickness)
{
	const vec2 p1Top2 = point2 - point1;
	const vec2 p1ToPosition = position - point1;
	float distanceAlongLine = clamp(dot(p1Top2, p1ToPosition) / dot2(p1Top2), 0.0, 1.0);
	return length(p1ToPosition - distanceAlongLine * p1Top2) - thickness;
}
 
float SDF_SlantedCapsule(
	const vec2 position,
	const vec2 point1,
	const float radius1,
	const vec2 point2,
	const float radius2)
{
    const vec2 ptoP1 = position - point1;
    const vec2 p1toP2 = point2 - point1;
    float distance = dot2(p1toP2);
 
    vec2 q = vec2(dot(ptoP1, vec2(p1toP2.y, -p1toP2.x)), dot(ptoP1, p1toP2)) / distance;
    q.x = abs(q.x);
    
    const float slope = radius1 - radius2;
    vec2 c = vec2(sqrt(distance - slope * slope), slope);
    
    float k = cross(vec3(c, 0), vec3(q,0)).x;
    float m = dot(c, q);
    float n = dot2(q);
    
	if( k < 0.0 ) return sqrt(distance * n) - radius1; // we are nearest point1
    if( k > c.x ) return sqrt(distance * (n + 1.0 - 2.0 * q.y)) - radius2; // we are nearest point2
	return m - radius1; // we are nearest the segment between point1 and point 2
}
 
float SDF_QuadraticBezier(
	const vec2 position, 
	const vec2 A, 
	const vec2 B,
	const vec2 C, 
	const float thickness)
{
	
	const vec2 a = B - A;
    const vec2 b = A - 2.0 * B + C;
    const vec2 c = a * 2.0;
    const vec2 d = A - position;
    const float kk = 1.0 / dot(b,b);
    const float kx = kk * dot(a,b);
    const float ky = kk * (2.0 * dot(a,a) + dot(d,b)) / 3.0;
    const float kz = kk * dot(d,a);      
    const float p = ky - kx * kx;
    const float p3 = p * p * p;
    const float q = kx * (2.0 * kx * kx - 3.0 * ky) + kz;
  	const float h = q * q + 4.0 * p3;
	
	float res = 0.0;
    if( h >= 0.0) 
    { 
		const float oneOverthree = 1.0 / 3.0;
        float sqrth = sqrt(h);
        vec2 x = (vec2(sqrth , -sqrth) - q) / 2.0;
        vec2 uv = sign(x) * pow(abs(x), vec2(oneOverthree,oneOverthree));
        float t = clamp( uv.x + uv.y - kx, 0.0, 1.0);
        res = dot2(d + (c + b * t) * t);
    } 
    else
    {
        const float z = sqrt(-p);
        const float v = acos( q / (p * z * 2.0) ) / 3.0;
		const float m = cos(v);
		const float n = sin(v) * RADIANT_SQRT3;
        vec3 t = clamp(vec3(m+m,-n-m,n-m) * z-kx, 0.0, 1.0);
        res = min( dot2(d+(c+b*t.x)*t.x),
				  dot2(d+(c+b*t.y)*t.y) );
    }
    return sqrt( res ) - thickness;
}
 
float SDF_Rhombus( 
	const vec2 position, 
	const vec2 extents ) 
{
	vec2 p = position;
	vec2 e = extents;
    e.y = -e.y;
    p = abs(p);
	float e2y = e.y * e.y;
    float h = clamp((dot(e, p) + e2y) / dot2(e), 0.0, 1.0);
    p -= e * vec2(h, h - 1.0f);
    return length(p) * sign(p.x);
}
 
float SDF_Parallelogram( 
	const vec2 position,
	const float width, 
	const float height, 
	const float skew )
{
    vec2 p = position;
    vec2 excentricity = vec2(skew,height);
    p = (p.y < 0.0) ? -p : p;
    vec2  w = p - excentricity;
    w.x -= clamp(w.x, -width, width);
    vec2  d = vec2(dot2(w), -w.y);
    float s = p.x * excentricity.y - p.y * excentricity.x;
    p = (s < 0.0) ? -p : p;
    vec2 v = p - vec2(width, 0); 
    v -= excentricity * clamp(dot(v,excentricity) / dot2(excentricity), -1.0, 1.0);
    d = min( d, vec2(dot2(v), width * height - abs(s)));
    return sqrt(d.x) * sign(-d.y);
}
 
float SDF_Triangle_Equilateral( 
	const vec2 position, 
	const float radius )
{
	vec2 pos = position;
    pos.x = abs(pos.x);
    pos -= vec2(0.5, 0.5 * RADIANT_SQRT3) * max(pos.x + RADIANT_SQRT3 * pos.y, 0.0);
    pos -= vec2(
		clamp(pos.x, -0.5 * radius * RADIANT_SQRT3, 0.5 * radius * RADIANT_SQRT3),
		-0.5 * radius);
 
    return length(pos) * sign(-pos.y);
}
 
float SDF_Triangle_Isoceles( 
	const vec2 position,
	const float width,
	const float height)
{
	const vec2 extents = vec2(width, height);
	vec2 pos = position;
	pos.y += height / 1.5f;
    pos.x = abs(pos.x);
    vec2 a = pos - extents * clamp( dot(pos, extents) / dot2(extents), 0.0, 1.0);
    vec2 b = pos - extents * vec2( clamp( pos.x / width, 0.0, 1.0), 1.0 );
    const float s = -sign( height );
    vec2 d = min( 
		vec2(dot2(a), s * (pos.x * height - pos.y * width)),
		vec2(dot2(b), s * (pos.y - height)));
 
    return -sqrt(d.x) * sign(d.y);
}
 
float SDF_Triangle( 
	const vec2 position, 
	const vec2 point1, 
	const vec2 point2, 
	const vec2 point3)
{
	const vec2 edge1 = point2 - point1;
	const vec2 edge2 = point3 - point2; 
	const vec2 edge3 = point1 - point3;
 
	const vec2 vertex1 = position - point1;
	const vec2 vertex2 = position - point2; 
	const vec2 vertex3 = position - point3;
 
    vec2 pq0 = vertex1 - edge1 * clamp( dot(vertex1,edge1) / dot2(edge1), 0.0, 1.0);
    vec2 pq1 = vertex2 - edge2 * clamp( dot(vertex2,edge2) / dot2(edge2), 0.0, 1.0);
    vec2 pq2 = vertex3 - edge3 * clamp( dot(vertex3,edge3) / dot2(edge3), 0.0, 1.0);
 
    float s = sign( edge1.x * edge3.y - edge1.y * edge3.x );
    vec2 d = min(min(
		vec2(dot2(pq0), s * (vertex1.x * edge1.y - vertex1.y * edge1.x)),
        vec2(dot2(pq1), s * (vertex2.x * edge2.y - vertex2.y * edge2.x))),
		vec2(dot2(pq2), s * (vertex3.x * edge3.y - vertex3.y * edge3.x)));
 
    return -sqrt(d.x) * sign(d.y);
}
 
float SDF_SymmetricTrapezoid( 
	const vec2 position, 
	const float height, 
	const float lowerHeight,
	const float upperHeight)
{
	vec2 pos = position;
	pos.x = abs(pos .x);
 
	const vec2 k1 = vec2(lowerHeight, height);
    const vec2 k2 = vec2(lowerHeight - upperHeight, 2.0 * height);
 
    vec2 ca = vec2(pos .x - (min(pos.x, (pos.y < 0.0) ? upperHeight : lowerHeight)), abs(pos.y) - height);
	vec2 cb = pos - k1 + k2 * clamp( dot(k1 - pos, k2) / dot2(k2), 0.0, 1.0 );
    
	float s = (cb.x < 0.0 && ca.y < 0.0) ? -1.0 : 1.0;   
	return s * sqrt( min( dot2(ca), dot2(cb)) );
}
 
float SDF_NPointedStar( 
	const vec2 position, 
	const float radius, 
	const float pointCount, 
	const float acuteness)
{
	vec2 pos = position;
	const float a = pointCount + acuteness * (2.0 - pointCount);
 
	const float pointAngle = RADIANT_PI / pointCount;
    const float accutnessAngle = RADIANT_PI / a; 
	
	vec2 racs = radius * cossin2(pointAngle);
    vec2 ecs = cossin2(accutnessAngle);
 
	pos.x = abs(pos.x);
	
    float bn = mod(atan(pos.x, pos.y) , 2.0 * pointAngle) - pointAngle;
	vec2 bncs = cossin2(bn);
 
    vec2 s = length(pos) * vec2(bncs.x, abs(bncs.y));
    s -= racs;
    s += ecs * clamp( -dot(s, ecs), 0.0, racs.y / ecs.y);
    return length(s) * sign(s.x);
}
 
float SDF_NGon( 
	const vec2 position, 
	const float radius, 
	const float pointCount)
{
	vec2 pos = position;
	float p = floor(pointCount);
 
	float pointAngle = RADIANT_PI / p;
	
	vec2 racs = radius * cossin2(pointAngle);
    const vec2 ecs = vec2(0.0,1.0);
 
	pos.x = abs(pos.x);
	
    float bn = mod(atan(pos.x, pos.y) , 2.0 * pointAngle) - pointAngle;
	vec2 bncs = cossin2(bn);
 
    vec2 s = length(pos) * vec2(bncs.x, abs(bncs.y));
    s -= racs;
    s += ecs * clamp( -dot(s, ecs), 0.0, racs.y);
    return length(s) * sign(s.x);
}
 
float SDF_Pentagon( 
	const vec2 position, 
	const float radius)
{
	vec2 pos = position;
 
	const vec3 slopes = vec3(0.809017,0.5877853,0.72654253);
	const float rSlopesZ = radius * slopes.z;
	const vec2 slopesminX_Y = vec2(-slopes.x, slopes.y);
 
    pos.x = abs(pos.x);
    vec2 s = pos - 2.0 * min(dot(slopesminX_Y , pos), 0.0) * slopesminX_Y ;
    s -= 2.0 * min(dot(slopes.xy, s), 0.0) * slopes.xy;
    s -= vec2(clamp(s.x, -rSlopesZ, rSlopesZ), radius);    
    return length(s) * sign(s.y);
}
 
float SDF_Hexagon( 
	const vec2 position, 
	const float radius)
{
 
	const vec3 slopes = vec3(-0.8660254,0.5,0.57735027);
	const float rSlopesZ = radius * slopes.z;
 
	vec2 s = abs(position);
    s -= 2.0 * min(dot(slopes.xy, s), 0.0) * slopes.xy;
    s -= vec2(clamp(s.x, -rSlopesZ, rSlopesZ), radius);
    return length(s) * sign(s.y);
}
 
float SDF_Octogon( 
	const vec2 position, 
	const float radius)
{
    const vec3 slopes = vec3(-0.9238795, 0.3826834, 0.4142136);
	const float rSlopesZ = radius * slopes.z;
	const vec2 slopesminX_Y = vec2(-slopes.x, slopes.y);
 
	
	vec2 s = abs(position);
    s -= 2.0 * min(dot(slopes.xy, s), 0.0) * slopes.xy;
    s -= 2.0 * min(dot(slopesminX_Y, s), 0.0) * slopesminX_Y;
    s -= vec2(clamp(s.x, -rSlopesZ, rSlopesZ), radius);
    return length(s) * sign(s.y);
}
 
float SDF_RingSegment(
	const vec2 position, 
	const float angle, 
	const float radius, 
	const float thickness )
{
	vec2 pos = position;
 
	float aRadians = clamp(angle * 0.5, 0.5f, 179.5) * RADIANT_DEG_TO_RAD;
	float c = cos(aRadians);
	float s = sin(aRadians);
	mat2 rm = mat2(vec2(c, -s), vec2(s, c));
	pos.x = abs(pos.x);
 
	vec2 rs = rm * pos;
 
	float halfThickness = thickness * 0.5;
    return max( abs(length(rs) - radius) - halfThickness ,
			   length(vec2(rs.x, max(0.0, abs(radius - rs.y) - halfThickness ))) * sign(rs.x) );
}
 
float SDF_CutCircle(
	const vec2 position, 
	const float radius, 
	const float cutheight)
{
	vec2 pos = position;
 
	const float clampedHeight = clamp(cutheight, 0.0001, RADIANT_NEARLY_ONE);
	const float adjCutHeight= (clampedHeight - 0.5f) * 2.f;
	const float cah = radius * adjCutHeight;
 
	const float w = sqrt(-cah * cah + (radius * radius));
    pos.x = abs(pos.x);
 
    const float cpa = cah + radius;
    const float cma = cah - radius;
    float chpx = cah * pos.x;
    float cmapx = cma * pos.x;
 
    float s = max( 
		cmapx * pos.x + (w * w * (- 2.0 * pos.y + cpa)), 
		-w * pos.y + chpx);
 
    return (s < 0.0) 
		? SDF_Circle(pos, radius) :  // circle
		(pos.x < w) ? cah - pos.y : // segment line
		length(pos - vec2(w, cah)); // segment corner
}
 
float SDF_Moon(
	const vec2 position,  
	const float distance,
	const float radius1,
	const float radius2)
{
	vec2 pos = position;
	pos.y = abs(pos.y);
 
	const float ra2 = radius1 * radius1;
	const float distance2 = distance * distance;
 
    float a = ((- radius2 * radius2 + ra2) + distance2 ) / (2.0 * distance);
    float b = sqrt(max(-a*a+ra2,0.0));
 
   return (distance * (-pos.y * a + (pos.x * b))) > (distance2 * max(b-pos.y, 0.0)) 
		? length(pos - vec2(a,b))
    	: max( length(pos) - radius1,
            -(length(pos - vec2(distance,0.0))-radius2));
}
 
float SDF_Quircle(
	const vec2 position,
	const float radius)
{
	vec2 pos = position / radius;
	pos = abs(pos); 
	pos =  pos.y > pos.x ? pos.yx : pos;
 
    float a = pos.x - pos.y;
    float b = pos.x + pos.y;
    float c = (2.0 * b + -1.0) * RADIANT_THIRD;
    float h = (a * a + (c * c * c));
    float t;
    if( h >= 0.0 )
    {   
        h = sqrt(h);
		float hma = h - a;
        t = sign(hma) * pow(abs(hma),RADIANT_THIRD) - pow(h + a,RADIANT_THIRD);
    }
    else
    {   
        float z = sqrt(-c);
        float v = acos(a / (c * z)) * RADIANT_THIRD;
        t = -z * (cos(v) + sin(v) * 1.732050808);
    }
    t *= 0.5;
    vec2 w = vec2(-t,t) + 0.75 - t * t - pos;
    return length(w) * sign( a * a * 0.5 + b - 1.5 ) * radius;
}
 
float SDF_Squircle(
	const vec2 position, 
	const float radius,
	const float roundness)
{               
	vec2 pos = position / radius;
    // symmetries
    pos = abs(pos);
	pos =  pos.y > pos.x ? pos.yx : pos;
 
    float xa = 0.0, xb = RADIANT_TAU * 0.125;
    for( int i=0; i<6; i++ )
    {
        float x = 0.5 * (xa + xb);
        float c = cos(x);
        float s = sin(x);
        float cn = pow(c, roundness);
        float sn = pow(s, roundness);
        float y = -(pos.y-sn) * sn * c * c + ((pos.x - cn) * cn * s * s);
 
        if( y < 0.0 ) xa = x;
		else xb = x;
    }
    // compute distance
	const vec2 roundessXY = vec2(roundness, roundness);
    vec2 qa = pow(vec2(cos(xa),sin(xa)), roundessXY);
    vec2 qb = pow(vec2(cos(xb),sin(xb)), roundessXY);
    vec2 pa = pos-qa, ba = qb-qa;
	float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
	return (length(-ba * h + pa) * sign(-pa.y * ba.x - (pa.x * ba.y))) * radius;
}
 
float SDF_Cross( 
	const vec2 position, 
	const float sidelength,
	const float armwidth, 
	const float cornerRadius) 
{
	vec2 pos = abs(position);
	pos = (pos.y > pos.x) ? pos.yx : pos;
	
	const vec2 b = vec2(sidelength, armwidth);
	vec2 q = pos - b;
	float k = max(q.y, q.x);
	vec2 w = k > 0.0 ? q : vec2(b.y - pos.x, -k);
	return sign(k) * length(max(w, 0.0)) + cornerRadius;
}
 
float SDF_Pie(
	const vec2 position,
	const float angle,
	const float radius)
{
	vec2 pos = position;
 
	pos.x = abs(pos.x);
	const float aRadians = clamp(angle * 0.5f, 0.5f, 179.5f) * RADIANT_DEG_TO_RAD;
	const vec2 center = vec2 (sin(aRadians), cos(aRadians));
    float l = length(pos) - radius;
    float m = length(pos - center * clamp(dot(pos, center), 0.f, radius));
    return max(l, m * sign(center.y * pos.x + (-center.x * pos.y)));
}
 
float SDF_Egg(
	const vec2 position,
	const float radiusA,
	const float radiusB,
	const float height,
	const float roundness)
{
    const float r = 0.5f * (height + radiusA + radiusB) / roundness;
    const float da = r - radiusA;
	const float da2 = da * da;
    const float db = r - radiusB;
    const float y = (db * db + (- da2 - height * height)) / (2.0f * height);
	const vec2 xy = vec2(sqrt(da2 - y * y), y);
	
	vec2 pos = position;
	pos.y = -pos.y;
	pos.x = abs(pos.x);
 
    float k = pos.y * xy.x - pos.x * xy.y;
    return k > 0.f && k < height * (pos.x + xy.x)
		? length(pos + xy) - r
    	: min(length(pos) - radiusA, length(vec2(pos.x, pos.y - height)) - radiusB );
}
 
float SDF_Heart( 
	const vec2 position )
{
	vec2 pos = position;
	pos.y = -pos.y + 0.5f;
	pos.x = abs(pos.x);
 
	float posXY = pos.x + pos.y;
	return posXY > 1.f
		? sqrt(dot2(pos - vec2(0.25f,0.75f))) - 0.35355339f
		: sqrt(min(dot2(pos - vec2(0.f,1.f)), dot2(pos - 0.5f * max(posXY, 0.f)))) * sign(pos.x - pos.y);
}
 
float SDF_RoundedX(
	const vec2 position,
	const float radius,
	const float width)
{
	vec2 pos = position;
    pos = abs(pos);
    return length(pos - min(pos.x + pos.y, width) * 0.5f) - radius;
}
 
float SDF_Ellipse(
	const vec2 position,
	const float width,
	const float height)
{
	// this is a degenerate case and needs to be handled as circle
	if (width == height) return SDF_Circle(position, width);
 
	vec2 pos = position;
	vec2 ab = vec2(width, height);
	pos = abs(pos); 
	if( pos.x > pos.y ) 
	{
		pos = pos.yx;
		ab = ab.yx;
	}
    
	float l = ab.y * ab.y + (- ab.x * ab.x);
	float OneOverL = 1.0 / l;
    float m = ab.x * pos.x * OneOverL;      
	float m2 = m*m; 
    float n = ab.y * pos.y * OneOverL;      
	float n2 = n*n; 
    float c = (m2 + n2 - 1.f) * RADIANT_THIRD;
	float c3 = c*c*c;
	float mn2 = m2*n2;
    float q = mn2 * 2.f + c3;
    float d = mn2 + c3;
    float g = m * n2 + m;
    float co;
 
    if( d<0.0 )
    {
        float h = acos(q / c3) * RADIANT_THIRD;
        float s = cos(h);
        float t = sin(h) * RADIANT_SQRT3;
        float rx = sqrt( -c * (s + t + 2.f) + m2 );
        float ry = sqrt( -c * (s - t + 2.f) + m2 );
        co = ((sign(l) * rx + (abs(g) / (rx * ry))) + ry - m) * 0.5f;
    }
    else
    {
        float h = 2.0 * m * n * sqrt( d );
        float s = sign(q + h) * pow(abs(q+h), RADIANT_THIRD);
        float u = sign(q - h) * pow(abs(q-h), RADIANT_THIRD);
        float rx = -s - u + -c * 4.0 + 2.0 * m2;
        float ry = (s - u) * RADIANT_SQRT3;
        float rm = sqrt( rx * rx + ry *ry );
        co = (ry / sqrt(rm - rx) + 2.0 * g / rm - m) * 0.5f;
    }
    vec2 r = ab * vec2(co, sqrt(1.0 - co * co));
    return length(r - pos) * sign(pos.y - r.y);
}