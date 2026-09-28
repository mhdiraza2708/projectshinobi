shader_type spatial;
// Textured ground: grass, dirt, rock and sand blended by per-vertex weights
// (COLOR: r grass, g dirt, b rock, a sand), each tinted to the island's
// palette, sampled in world space at two scales so repeats don't show.
// Rock is projected from the side on steep ground so cliffs don't smear.
// With arena_radius > 0 the weights come from distance instead: a dirt
// arena with a ragged edge inside grass (the training ground).

uniform sampler2D grass_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dirt_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dirt_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D sand_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D sand_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D noise : filter_linear_mipmap, repeat_enable;

uniform vec3 grass_tint = vec3(1.0);
// Grass drifts toward this tint in broad patches (an island's second green).
uniform vec3 grass_tint2 = vec3(1.0);
uniform vec3 dirt_tint = vec3(1.0);
uniform vec3 rock_tint = vec3(1.0);
uniform vec3 sand_tint = vec3(1.0);
// Metres per texture repeat.
uniform float tile_size = 4.0;
uniform float arena_radius = 0.0;
uniform float arena_edge = 2.5;
// Ground below this is wet (darker, glossier) sea bed.
uniform float water_level = -1000.0;

varying vec3 world_pos;
varying vec3 world_normal;
varying vec4 weights;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	weights = COLOR;
	// Texture space follows world X/Z (the meshes carry no tangents of their own).
	TANGENT = normalize(vec3(1.0, 0.0, 0.0) - NORMAL * NORMAL.x);
	BINORMAL = cross(NORMAL, TANGENT);
}

vec3 two_scale(sampler2D tex, vec2 uv, vec2 uv2) {
	return mix(texture(tex, uv).rgb, texture(tex, uv2).rgb, 0.35);
}

void fragment() {
	vec2 uv = world_pos.xz / tile_size;
	vec2 uv2 = world_pos.xz / (tile_size * 2.7) + vec2(0.37, 0.61);
	float n = texture(noise, world_pos.xz * 0.03).r;
	float n2 = texture(noise, world_pos.xz * 0.011 + vec2(0.5)).r;
	vec4 w = weights;
	if (arena_radius > 0.0) {
		float d = length(world_pos.xz) + (n - 0.5) * arena_edge * 2.0;
		float dirt = 1.0 - smoothstep(arena_radius - arena_edge, arena_radius + arena_edge * 0.4, d);
		w = vec4(1.0 - dirt, dirt, 0.0, 0.0);
	}
	w = max(w, vec4(0.0));
	w /= max(w.r + w.g + w.b + w.a, 1e-3);

	vec3 col = vec3(0.0);
	vec3 nm = vec3(0.0);
	if (w.r > 0.002) {
		vec3 tint = mix(grass_tint, grass_tint2, smoothstep(0.35, 0.65, n2));
		col += two_scale(grass_albedo, uv, uv2) * tint * w.r;
		nm += texture(grass_normal, uv).rgb * w.r;
	}
	if (w.g > 0.002) {
		col += two_scale(dirt_albedo, uv, uv2) * dirt_tint * w.g;
		nm += texture(dirt_normal, uv).rgb * w.g;
	}
	if (w.b > 0.002) {
		// Top-down on gentle ground, from the side on cliffs.
		vec3 bw = pow(abs(world_normal), vec3(4.0));
		bw /= bw.x + bw.y + bw.z;
		vec2 ruv = uv * 0.7;
		vec3 rock = texture(rock_albedo, ruv).rgb * bw.y
			+ texture(rock_albedo, world_pos.zy / tile_size * 0.7).rgb * bw.x
			+ texture(rock_albedo, world_pos.xy / tile_size * 0.7).rgb * bw.z;
		col += rock * rock_tint * w.b;
		nm += mix(texture(rock_normal, ruv).rgb, vec3(0.5, 0.5, 1.0), 1.0 - bw.y) * w.b;
	}
	if (w.a > 0.002) {
		col += two_scale(sand_albedo, uv, uv2) * sand_tint * w.a;
		nm += texture(sand_normal, uv).rgb * w.a;
	}
	// Broad light/dark patches so big open ground isn't uniform.
	col *= 0.88 + 0.24 * n;
	float wet = smoothstep(water_level + 0.2, water_level - 1.5, world_pos.y);
	col *= 1.0 - 0.45 * wet;
	ALBEDO = col;
	NORMAL_MAP = nm;
	NORMAL_MAP_DEPTH = 1.0;
	ROUGHNESS = mix(0.95, 0.35, wet);
	SPECULAR = 0.2;
}
