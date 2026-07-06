// sRGB-linear -> OKLab and back
vec3 to_oklab(vec3 c) {
	mat3 m1 = mat3(
		vec3(0.4122214708, 0.2119034982, 0.0883024619),
		vec3(0.5363325363, 0.6806995451, 0.2817188376),
		vec3(0.0514459929, 0.1073969566, 0.6299787005));
	vec3 lms = m1 * c;
	lms = pow(max(lms, vec3(0.0)), vec3(1.0 / 3.0));
	mat3 m2 = mat3(
		vec3(0.2104542553,  1.9779984951,  0.0259040371),
		vec3(0.7936177850, -2.4285922050,  0.7827717662),
		vec3(-0.0040720468, 0.4505937099, -0.8086757660));
	return m2 * lms;
}

vec3 from_oklab(vec3 c) {
	mat3 m1 = mat3(
		vec3(1.0,  1.0,  1.0),
		vec3(0.3963377774, -0.1055613458, -0.0894841775),
		vec3(0.2158037573, -0.0638541728, -1.2914855480));
	vec3 lms = m1 * c;
	lms = lms * lms * lms;
	mat3 m2 = mat3(
		vec3(4.0767416621, -1.2684380046, -0.0041960863),
		vec3(-3.3077115913, 2.6097574011, -0.7034186147),
		vec3(0.2309699292, -0.3413193965,  1.7076147010));
	return m2 * lms;
}

vec3 adjust_lightness(vec3 c, float delta) {
	vec3 lab = to_oklab(c);
	lab.x = clamp(lab.x + delta, 0.0, 1.0);
	return from_oklab(lab);
}