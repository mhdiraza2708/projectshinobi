shader_type spatial;
// A summoning seal on the ground: rings, turning ticks and a five-pointed
// star, drawn additively so it glows over any ground.
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec4 color : source_color = vec4(0.55, 0.8, 1.0, 1.0);
uniform float strength = 1.0;

float line(float d, float w) {
	return smoothstep(w, 0.0, abs(d));
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float a = atan(p.y, p.x);
	float spin = TIME * 0.7;
	float rings = line(r - 0.93, 0.018) + line(r - 0.82, 0.012) + line(r - 0.47, 0.012);
	float ticks = step(0.83, r) * step(r, 0.92) * smoothstep(0.55, 0.95, sin(a * 30.0 + spin * 4.0));
	// Star: the line between each point and the point two steps on.
	float star = 0.0;
	for (int i = 0; i < 5; i++) {
		float a0 = spin + 6.2831853 * float(i) / 5.0;
		float a1 = spin + 6.2831853 * float(i + 2) / 5.0;
		vec2 p0 = vec2(cos(a0), sin(a0)) * 0.8;
		vec2 p1 = vec2(cos(a1), sin(a1)) * 0.8;
		vec2 d = p1 - p0;
		float h = clamp(dot(p - p0, d) / dot(d, d), 0.0, 1.0);
		star += line(length(p - p0 - d * h), 0.012);
	}
	float glow = exp(-r * 2.5) * 0.4;
	float v = (rings + ticks * 0.8 + min(star, 1.0) + glow) * step(r, 1.0);
	ALBEDO = color.rgb * v * strength * 1.8;
}
