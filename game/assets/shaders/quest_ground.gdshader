shader_type spatial;
// The light pooled at the foot of the mission pillar: a soft glow, a ring
// that breathes, a broken outer ring turning slowly and ripples spreading
// out from the middle. Drawn additively so it glows over any ground.
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec4 color : source_color = vec4(1.0, 0.8, 0.42, 1.0);
uniform float strength = 1.0;

float line(float d, float w) {
	return smoothstep(w, 0.0, abs(d));
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float a = atan(p.y, p.x);
	float breath = 0.88 + 0.12 * sin(TIME * 1.7);
	float pool = pow(1.0 - clamp(r, 0.0, 1.0), 2.0) * 0.4;
	float ring = line(r - 0.74, 0.07) * 0.85 * breath + line(r - 0.74, 0.016);
	float inner = line(r - 0.5, 0.018) * 0.35;
	float broken = line(r - 0.9, 0.025) * smoothstep(-0.2, 0.5, sin(a * 5.0 - TIME * 0.5)) * 0.7;
	float t = fract(TIME * 0.22);
	float ripple = line(r - t * 0.85, 0.05) * (1.0 - t) * 0.6;
	float v = (pool + ring + inner + broken + ripple) * (1.0 - smoothstep(0.9, 1.0, r));
	ALBEDO = color.rgb * v * strength * 1.8;
}
