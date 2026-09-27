shader_type spatial;
// Stylised water for the islands: gentle swell, rippling normals, a
// fresnel shift from deep to shallow colour. `falling` turns it into a
// waterfall sheet (streaks sliding down instead of ripples).
render_mode cull_disabled, specular_schlick_ggx;

uniform vec4 deep : source_color = vec4(0.11, 0.31, 0.4, 1.0);
uniform vec4 shallow : source_color = vec4(0.25, 0.54, 0.57, 1.0);
uniform float swell = 0.18;
uniform float falling = 0.0;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	if (falling < 0.5) {
		float h = sin(world_pos.x * 0.13 + TIME * 0.7) * 0.5 + sin(world_pos.z * 0.19 - TIME * 0.55) * 0.5;
		VERTEX.y += h * swell;
	}
}

void fragment() {
	float t = TIME;
	if (falling > 0.5) {
		// Vertical streaks rushing down, foamy at the bottom.
		float streak = sin(UV.x * 90.0 + sin(UV.x * 13.0) * 3.0) * 0.5 + 0.5;
		float flow = fract(UV.y * 2.5 - t * 1.6 + streak * 0.3);
		float foam = smoothstep(0.75, 1.0, UV.y) + smoothstep(0.55, 1.0, flow) * 0.5;
		ALBEDO = mix(deep.rgb, shallow.rgb, clamp(streak * 0.4 + foam, 0.0, 1.0));
		ALPHA = 0.85;
		ROUGHNESS = 0.3;
	} else {
		vec2 p = world_pos.xz;
		vec3 n = normalize(vec3(
			sin(p.x * 0.9 + t * 1.3) * 0.07 + sin(p.y * 1.7 - t * 0.9) * 0.05 + sin((p.x + p.y) * 2.3 + t * 1.7) * 0.03,
			1.0,
			cos(p.y * 0.8 + t * 1.1) * 0.07 + cos(p.x * 1.3 + t * 0.7) * 0.05 + cos((p.x - p.y) * 2.1 - t * 1.5) * 0.03));
		NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
		float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
		ALBEDO = mix(deep.rgb, shallow.rgb, 0.25 + 0.5 * fres);
		ROUGHNESS = 0.06;
		SPECULAR = 0.6;
	}
}
