shader_type spatial;
// Surf where land meets the sea: a soft white band along the waterline that
// breaks into lacy streaks, rolls in toward the shore and thins out to sea.
// The mesh is a strip along the coast (ShoreFoam) whose UV.y is the distance
// in metres from the waterline (negative on the land side, where the ground
// hides it) and whose UV.x is how far out to sea it reaches. It rides the
// same swell as the sea (water.gdshader), so a wave never washes over it.
render_mode blend_mix, depth_draw_never, cull_disabled, specular_disabled, shadows_disabled;

uniform vec3 color : source_color = vec3(0.95, 0.98, 1.0);
// Must match water.gdshader's swell, which the foam floats on.
uniform float swell = 0.18;
// The foam is drawn out to fade_end metres and thins out from fade_start.
uniform float fade_start = 900.0;
uniform float fade_end = 1350.0;

varying vec3 world_pos;
varying float far_fade;
// How far out this strip's surf reaches, in metres (UV.x).
varying float reach;

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	reach = UV.x;
	float h = sin(world_pos.x * 0.13 + TIME * 0.7) * 0.5 + sin(world_pos.z * 0.19 - TIME * 0.55) * 0.5;
	// Far away the depth buffer can't tell the foam from the sea under it, so
	// it rides a little higher the further it is (never noticeable).
	float dist = length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
	VERTEX.y += h * swell + 0.1 + dist * dist * 2.2e-6;
	far_fade = 1.0 - smoothstep(fade_start, fade_end, dist);
}

void fragment() {
	float d = UV.y;
	float t = TIME;
	vec2 p = world_pos.xz;
	// Broad, slow patchiness, and a finer lace that drifts.
	float n = value_noise(p * 0.22 + vec2(t * 0.04, -t * 0.03));
	float lace = value_noise(p * 1.7 + vec2(-t * 0.16, t * 0.09)) * 0.6 + value_noise(p * 3.9 + vec2(t * 0.11, t * 0.18)) * 0.4;

	// The swash: a ragged white edge at the waterline that surges in and out.
	float surge = 1.2 + 0.8 * n + 0.5 * sin(t * 0.6 + n * 7.0);
	float edge = 1.0 - smoothstep(0.0, surge, d);
	float foam_edge = smoothstep(0.28, 0.5, edge + (lace - 0.5) * 0.8);

	// Swells of foam rolling in: a sharp leading edge, a trailing wake, and
	// the lace eating holes in them.
	float f = fract(d * 0.27 + t * 0.15 + n * 0.9);
	float wave = smoothstep(0.0, 0.05, f) * (1.0 - smoothstep(0.06, 0.4, f));
	float out_fade = 1.0 - smoothstep(0.0, reach, d);
	float foam_wave = smoothstep(0.4, 0.6, wave * out_fade + (lace - 0.5) * 0.7) * out_fade;

	// A thin haze of foam over the shallows.
	float haze = smoothstep(0.55, 0.8, lace * 0.6 + n * 0.5) * (1.0 - smoothstep(0.0, reach * 0.9, d)) * 0.35;

	float strength = max(foam_edge, max(foam_wave * 0.85, haze));
	// The land side fades out under the sand, the sea side at the reach.
	strength *= smoothstep(-2.4, -0.4, d) * (1.0 - smoothstep(reach * 0.85, reach, d));
	ALBEDO = mix(color * vec3(0.8, 0.92, 0.96), color, smoothstep(0.1, 0.7, strength));
	ROUGHNESS = 1.0;
	ALPHA = strength * 0.9 * far_fade;
}
