shader_type spatial;
// Textured ground: grass, dirt, rock and sand blended by per-vertex weights
// (COLOR: r grass, g dirt, b rock, a sand), each tinted to the island's
// palette, sampled in world space at two scales so repeats don't show.
// The layers are photo-scanned (art/polyhaven/fetch.py), each repeating at
// its real size, and blend by height: where grass meets dirt, the dirt
// shows first in the hollows and the grass keeps the tops, the way a real
// edge looks, instead of a soft cross-fade. (Each normal map carries its
// surface's height in blue; Godot rebuilds a normal's Z itself.)
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
// Metres per texture repeat: grass, dirt, rock, sand.
uniform vec4 tile_sizes = vec4(4.0);
// Surface roughness of each layer.
uniform vec4 roughness = vec4(0.95, 0.92, 0.8, 0.9);
// How far (in height, 0-1) one layer's bumps poke through another's.
uniform float blend_depth = 0.25;
uniform float arena_radius = 0.0;
uniform float arena_edge = 2.5;
// Ground below this is wet (darker, glossier) sea bed.
uniform float water_level = -1000.0;
// Rain darkens and glosses everything a little (0-1).
uniform float wetness = 0.0;

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

// A layer's colour, mixed from two scales so its repeat doesn't show.
vec3 two_scale(sampler2D tex, vec2 p, float tile) {
	vec2 uv = p / tile;
	vec2 uv2 = p / (tile * 2.7) + vec2(0.37, 0.61);
	return mix(texture(tex, uv).rgb, texture(tex, uv2).rgb, 0.35);
}

void fragment() {
	vec2 p = world_pos.xz;
	float n = texture(noise, p * 0.03).r;
	float n2 = texture(noise, p * 0.011 + vec2(0.5)).r;
	vec4 w = weights;
	if (arena_radius > 0.0) {
		float d = length(p) + (n - 0.5) * arena_edge * 2.0;
		float dirt = 1.0 - smoothstep(arena_radius - arena_edge, arena_radius + arena_edge * 0.4, d);
		w = vec4(1.0 - dirt, dirt, 0.0, 0.0);
	}
	w = max(w, vec4(0.0));
	w /= max(w.r + w.g + w.b + w.a, 1e-3);

	// Normal (xy) and height (z) of each layer present.
	vec3 nh_grass = vec3(0.5, 0.5, 0.5);
	vec3 nh_dirt = nh_grass;
	vec3 nh_rock = nh_grass;
	vec3 nh_sand = nh_grass;
	vec3 c_grass = vec3(0.0);
	vec3 c_dirt = vec3(0.0);
	vec3 c_rock = vec3(0.0);
	vec3 c_sand = vec3(0.0);
	if (w.r > 0.002) {
		vec3 tint = mix(grass_tint, grass_tint2, smoothstep(0.35, 0.65, n2));
		c_grass = two_scale(grass_albedo, p, tile_sizes.x) * tint;
		nh_grass = texture(grass_normal, p / tile_sizes.x).rgb;
	}
	if (w.g > 0.002) {
		c_dirt = two_scale(dirt_albedo, p, tile_sizes.y) * dirt_tint;
		nh_dirt = texture(dirt_normal, p / tile_sizes.y).rgb;
	}
	if (w.b > 0.002) {
		// Top-down on gentle ground, from the side on cliffs.
		vec3 bw = pow(abs(world_normal), vec3(4.0));
		bw /= bw.x + bw.y + bw.z;
		float t = tile_sizes.z;
		vec3 rock = texture(rock_albedo, p / t).rgb * bw.y
			+ texture(rock_albedo, world_pos.zy / t).rgb * bw.x
			+ texture(rock_albedo, world_pos.xy / t).rgb * bw.z;
		c_rock = rock * rock_tint;
		vec3 top = texture(rock_normal, p / t).rgb;
		// Cliff faces keep the scanned height for blending but a flat normal
		// (the top-down normal map doesn't fit a wall).
		nh_rock = vec3(mix(top.xy, vec2(0.5), 1.0 - bw.y), top.z);
	}
	if (w.a > 0.002) {
		c_sand = two_scale(sand_albedo, p, tile_sizes.w) * sand_tint;
		nh_sand = texture(sand_normal, p / tile_sizes.w).rgb;
	}

	// Height blend: each layer's weight raised by its own surface height,
	// and only what comes within blend_depth of the highest survives.
	vec4 h = vec4(nh_grass.z, nh_dirt.z, nh_rock.z, nh_sand.z);
	vec4 hw = w + h * 0.5 * step(0.002, w);
	float top_h = max(max(hw.r, hw.g), max(hw.b, hw.a)) - blend_depth;
	vec4 b = max(hw - top_h, vec4(0.0)) * step(0.002, w);
	b /= max(b.r + b.g + b.b + b.a, 1e-4);

	vec3 col = c_grass * b.r + c_dirt * b.g + c_rock * b.b + c_sand * b.a;
	vec2 nxy = nh_grass.xy * b.r + nh_dirt.xy * b.g + nh_rock.xy * b.b + nh_sand.xy * b.a;
	float rough = dot(roughness, b);
	float height = dot(h, b);

	// Broad light/dark patches so big open ground isn't uniform.
	col *= 0.88 + 0.24 * n;
	float wet = max(smoothstep(water_level + 0.2, water_level - 1.5, world_pos.y),
		// Rain pools in the low parts first.
		wetness * (0.55 + 0.45 * (1.0 - height)));
	col *= 1.0 - 0.45 * wet;
	ALBEDO = col;
	NORMAL_MAP = vec3(nxy, 1.0);
	NORMAL_MAP_DEPTH = 1.0;
	ROUGHNESS = mix(rough, 0.3, wet);
	SPECULAR = 0.35;
}
