shader_type spatial;
// Glowing energy: bright at the silhouette (fresnel), with noise scrolling
// through it. Orbs, water lances, auras and shields. Additive.
render_mode unshaded, blend_add, cull_back, depth_draw_never, shadows_disabled;

uniform vec4 color : source_color = vec4(0.5, 0.8, 1.0, 1.0);
uniform float intensity = 1.4;
// Higher = thinner rim.
uniform float rim_power = 2.2;
// How much the middle glows (0 = hollow shell).
uniform float core = 0.25;
uniform float scroll = 0.8;
uniform float fade = 1.0;
uniform sampler2D noise : source_color, repeat_enable, filter_linear;

void fragment() {
	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float rim = pow(1.0 - facing, rim_power);
	float n = texture(noise, UV * vec2(3.0, 1.5) + vec2(TIME * 0.13, -TIME * scroll)).r;
	float n2 = texture(noise, UV * vec2(5.0, 2.5) - vec2(TIME * 0.21, TIME * scroll * 0.6)).r;
	float swirl = n * 0.6 + n2 * 0.4;
	float v = rim * (0.55 + 0.9 * swirl) + core * pow(facing, 2.0) * (0.4 + 0.8 * swirl);
	ALBEDO = color.rgb * v * intensity * fade + vec3(0.6) * pow(rim, 4.0) * fade;
}
