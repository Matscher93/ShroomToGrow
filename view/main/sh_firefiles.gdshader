shader_type canvas_item;

uniform vec2 rect_size;
uniform vec4 box_color : source_color;

float rand21(vec2 p) {
    return fract(sin(dot(p, vec2(243.57, 1472.83))) * 2534978.689);
}

vec2 rand22(vec2 p) {
    float r1 = rand21(p);
    return vec2(r1, rand21(r1 * p));
}

vec2 getPoint(vec2 id) {
    vec2 r = rand22(id);
    float time = TIME * 2.0;

    vec2 speed = rand22(id + rand22(id));

    float x = fract(r.x);
    float y = fract(r.y);

    return vec2(x, y);
}


vec4 mainImage( vec2 fragCoord )
{
    const float ZOOM = 10.0;
    vec3 col = vec3(0.);

    vec2 uv = fragCoord.xy / rect_size.xy;
    vec2 orig_uv = uv;
    uv.x *= rect_size.x / rect_size.y;
    uv *= ZOOM;
    uv.y += TIME/8.0;

    vec2 id = floor(uv);
    vec2 gv = fract(uv);

    float presence = 0.;
    for (int x = -1; x < 2; x++) {
        for (int y = -1; y < 2; y++) {
            vec2 offset = vec2(float(x), float(y));

            vec2 nid = id + offset;
            vec2 np = getPoint(nid);

            float size = clamp(rand21(nid) * .01 * (sin(TIME+nid.x*nid.y) + 1.5), 0.01, 1.0);

            float x2 = distance(offset + np, gv);
            float y2 = max(size / x2 - size, .0);
            presence += y2;
        }
    }

    vec3 base_color = box_color.xyz;
    col = base_color * presence;
    return vec4(col, presence);
}

void fragment() {
	vec4 sparks = mainImage(UV * rect_size);
	COLOR = vec4(sparks.xyz, (clamp(sparks.a, 0.0, 1.0)* UV.y-0.7)*3.0);
}