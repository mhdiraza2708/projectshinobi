shader_type canvas_item;
// Film grain and a soft vignette over the 3D view (the Cinematic preset).

uniform float grain = 0.045;
uniform float vignette = 0.42;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	// Grain changes every frame, centred on mid grey so it neither brightens
	// nor darkens on average.
	float n = hash(floor(FRAGCOORD.xy) + vec2(fract(TIME * 13.0) * 97.0, fract(TIME * 7.0) * 61.0)) - 0.5;
	float d = distance(uv, vec2(0.5)) * 1.25;
	float v = smoothstep(0.45, 1.05, d) * vignette;
	// Darken toward the corners, then lay the grain over the top.
	vec3 col = vec3(0.5 + n);
	float a = clamp(grain * 2.0 + v, 0.0, 1.0);
	col = mix(col, vec3(0.0), v / max(a, 0.001));
	COLOR = vec4(col, a);
}
