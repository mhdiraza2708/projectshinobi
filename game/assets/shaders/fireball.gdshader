shader_type spatial;
// A boiling ball of fire: white-hot where you see into it, orange then red
// toward the edge, with noise churning upward through it. Alpha-blended so
// it stays fiery (not white) over bright ground; add a glow for the bloom.
render_mode unshaded, blend_mix, cull_back, depth_draw_never, shadows_disabled;

uniform vec4 hot : source_color = vec4(1.0, 0.95, 0.7, 1.0);
uniform vec4 mid : source_color = vec4(1.0, 0.5, 0.08, 1.0);
uniform vec4 edge : source_color = vec4(0.75, 0.1, 0.02, 1.0);
uniform float intensity = 1.3;
uniform sampler2D noise : source_color, repeat_enable, filter_linear;

void fragment() {
	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float n = texture(noise, UV * vec2(4.0, 2.0) + vec2(TIME * 0.2, -TIME * 1.1)).r;
	float n2 = texture(noise, UV * vec2(7.0, 3.5) + vec2(-TIME * 0.3, -TIME * 1.7)).r;
	float heat = clamp(facing * 1.15 + (n * 0.6 + n2 * 0.4 - 0.5) * 0.9, 0.0, 1.0);
	vec3 col = mix(edge.rgb, mid.rgb, smoothstep(0.15, 0.55, heat));
	col = mix(col, hot.rgb, smoothstep(0.6, 0.95, heat));
	ALBEDO = col * min(0.55 + heat * 0.6, 1.0) * intensity;
	ALPHA = smoothstep(0.02, 0.35, heat + facing * 0.3);
}
