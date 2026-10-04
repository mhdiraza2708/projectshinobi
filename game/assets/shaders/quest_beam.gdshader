shader_type spatial;
// The pillar of light over the next mission: a soft beam, brightest at the
// foot and fading away toward the sky, its edges melting off by a fresnel
// falloff, breathing gently. It widens with distance so it stays a bright
// line across the sea, and thins to nothing near the camera so it never
// fills the screen when you stand in it.
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec4 color : source_color = vec4(1.0, 0.8, 0.42, 1.0);
uniform float strength = 1.0;
// The mesh's height in metres (its middle is the origin).
uniform float height = 160.0;
// Higher: a narrower bright middle and softer edges.
uniform float edge_power = 1.5;
// Higher: the light thins out sooner on the way up.
uniform float fade_power = 1.6;
// Metres of radius added per metre of distance from the camera.
uniform float widen = 0.004;
// Camera distance where it starts to fade away, and where it's all gone.
uniform vec2 near_fade = vec2(6.0, 22.0);

varying float up;

void vertex() {
	up = clamp(VERTEX.y / height + 0.5, 0.0, 1.0);
	float r = length(VERTEX.xz);
	if (r > 0.001) {
		float d = distance((MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz, CAMERA_POSITION_WORLD);
		VERTEX.xz *= 1.0 + d * widen / r;
	}
}

void fragment() {
	// 1 down the middle of the beam as you see it, 0 at its edges.
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float edge = pow(facing, edge_power);
	float rise = pow(1.0 - up, fade_power) * smoothstep(0.0, 0.02, up);
	float metres = up * height;
	float breath = 0.9 + 0.1 * sin(TIME * 1.7);
	float shimmer = 0.92 + 0.08 * sin(metres * 0.3 - TIME * 2.4);
	float near = smoothstep(near_fade.x, near_fade.y, length(VERTEX));
	ALBEDO = color.rgb * strength * edge * rise * breath * shimmer * near;
}
