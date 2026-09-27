shader_type spatial;
// A column of light: bright at the base, fading upward, with bands rushing up.
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec4 color : source_color = vec4(0.55, 0.8, 1.0, 1.0);
uniform float strength = 1.0;

void fragment() {
	float base = pow(UV.y, 2.2);
	float bands = 0.65 + 0.35 * sin(UV.y * 40.0 + TIME * 14.0);
	float rim = 1.0 - abs(dot(NORMAL, VIEW));
	ALBEDO = color.rgb * base * bands * (0.15 + rim) * strength * 1.1;
}
