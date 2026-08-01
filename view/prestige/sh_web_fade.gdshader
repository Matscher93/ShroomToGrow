shader_type canvas_item;
render_mode unshaded;
// Fades the perk web out towards the edges of its clip rect instead of letting
// PerkWeb's clip_contents cut nodes and lines off mid-stroke. Sits on the
// "World" CanvasGroup, which flattens the whole web (lines + node shaders) into
// one image, so a single alpha ramp fades it evenly.
//
// A CanvasGroup renders its children into the backbuffer, not into TEXTURE, so
// the content has to be read through hint_screen_texture and un-premultiplied -
// this mirrors Godot's built-in canvas group material. Sampling TEXTURE instead
// just yields the default white texture.
//
// The rect is screen-space for the same reason: the group's own UVs only span
// its children's bounding box, which grows and shifts with pan and zoom.
// gd_perk_web.gd pushes the clip rect in SCREEN_UV units.

uniform sampler2D group_texture : hint_screen_texture, repeat_disable, filter_nearest;
uniform vec2 rect_min = vec2(0.0);
uniform vec2 rect_max = vec2(1.0);
uniform vec2 fade_size = vec2(0.05);

void fragment() {
	vec2 fade = max(fade_size, vec2(0.0001));
	vec2 from_min = smoothstep(vec2(0.0), fade, SCREEN_UV - rect_min);
	vec2 from_max = smoothstep(vec2(0.0), fade, rect_max - SCREEN_UV);
	// Reaches 0 exactly at the rect edge, so the shader also does the clipping.
	float alpha = from_min.x * from_min.y * from_max.x * from_max.y;

	vec4 group_color = textureLod(group_texture, SCREEN_UV, 0.0);
	if (group_color.a > 0.0001) {
		group_color.rgb /= group_color.a;
	}
	COLOR *= group_color;
	COLOR.a *= alpha;
}
