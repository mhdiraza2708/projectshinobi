shader_type canvas_item;
// The cut-in when a dojutsu opens: black, two eyes under hanging bangs; the
// bangs whip aside, the lids snap open and the eye art's pattern spins into
// the irises. Drawn rather than rendered from the model, so it works for
// any character, even one whose eyes are never modelled under the hair.
//
// Units: screen heights, (0, 0) at the centre, y down.

uniform float aspect = 1.7778;
uniform int pattern = 0;
uniform vec3 color : source_color = vec3(0.9, 0.6, 0.2);
uniform float awakened : hint_range(0.0, 1.0) = 0.0;
// Extra turn (radians) while the pattern spins into place.
uniform float spin = 0.0;
// 0 = shut (a glowing seam), 1 = wide open.
uniform float lids = 0.0;
// 0 = bangs hanging over the eyes, 1 = swept aside.
uniform float hair = 0.0;
// 0 = an ordinary eye, 1 = the pattern fully drawn.
uniform float intensity = 0.0;
// The burst as the eyes open: speed lines and a bright rim.
uniform float burst = 0.0;
// The whole cut-in's opacity.
uniform float fade = 1.0;
uniform float glow = 1.2;

#include "res://assets/shaders/eye_patterns.gdshaderinc"

// The right eye's centre and size (the left mirrors it).
const vec2 EYE = vec2(0.36, 0.04);
const vec2 EYE_SIZE = vec2(0.27, 0.14);
const float IRIS = 0.105;
const int STRANDS = 22;

float hash(float n) {
	return fract(sin(n * 12.9898) * 43758.5453);
}

// The eye's opening between the lids, in the eye's own units (x from -1 at
// the inner corner to 1 at the outer, y down): x = upper lid, y = lower lid.
vec2 opening(float x) {
	float w = max(0.0, 1.0 - x * x);
	float tilt = -0.12 * x;
	return vec2(-lids * pow(w, 0.6) * (1.0 - 0.18 * x) + tilt, lids * 0.55 * pow(w, 0.9) + tilt);
}

// One eye: rgb, and alpha where anything of it shows.
vec4 eye(vec2 p) {
	vec2 q = (p - EYE) / EYE_SIZE;
	vec4 out_col = vec4(0.0);
	if (abs(q.x) > 1.05) {
		return out_col;
	}
	vec2 lid = opening(q.x);
	float soft = 0.035;
	float inside = smoothstep(lid.x - soft, lid.x + soft, q.y) * (1.0 - smoothstep(lid.y - soft, lid.y + soft, q.y));
	inside *= 1.0 - smoothstep(0.92, 1.0, abs(q.x));
	// The white, shadowed under the upper lid.
	float depth = clamp((q.y - lid.x) / max(lid.y - lid.x, 0.001), 0.0, 1.0);
	vec3 col = vec3(0.9, 0.9, 0.94) * mix(0.45, 1.0, smoothstep(0.0, 0.45, depth));
	// The iris: an ordinary dark eye until the pattern comes.
	vec2 c = EYE + vec2(0.0, 0.012);
	vec2 ip = (p - c) / IRIS;
	ip.y = -ip.y;
	float r = length(ip);
	if (r < 1.0) {
		float a = atan(ip.y, ip.x);
		vec2 m;
		if (pattern == 0) {
			m = hawk(ip, r, a, awakened);
		} else if (pattern == 1) {
			m = mirror(ip, r, a, awakened);
		} else if (pattern == 2) {
			m = seal(ip, r, a, awakened);
		} else {
			m = still(ip, r, a, awakened);
		}
		float rim = smoothstep(0.8, 1.0, r);
		vec3 plain = mix(vec3(0.22, 0.2, 0.22), vec3(0.04), step(r, 0.26)) * (1.0 - rim * 0.6);
		vec3 iris = color * mix(1.25, 0.55, r) * (1.0 - rim * 0.7);
		float lit = clamp(m.y, 0.0, 1.0);
		vec3 drawn = mix(iris, vec3(INK), m.x * (1.0 - lit));
		drawn = mix(drawn, color * (1.0 + glow), lit);
		vec3 icol = mix(plain, drawn, intensity);
		// A highlight, top left, as in any drawn eye.
		float shine = 1.0 - smoothstep(0.1, 0.16, length(ip - vec2(-0.38, 0.4)));
		icol = mix(icol, vec3(1.0), shine * 0.9);
		col = mix(col, icol, 1.0 - smoothstep(0.97, 1.0, r));
		// The lid's shadow falls over the top of the iris too.
		col *= mix(0.55, 1.0, smoothstep(0.0, 0.35, depth));
	}
	out_col = vec4(col, inside);
	// A seam of light along the lids: faint while shut, bright as they open.
	float seam_u = abs(q.y - lid.x) * EYE_SIZE.y;
	float seam_l = abs(q.y - lid.y) * EYE_SIZE.y;
	float along = 1.0 - smoothstep(0.85, 1.0, abs(q.x));
	float seam = (exp(-seam_u * 160.0) + exp(-seam_l * 160.0) * 0.6) * along;
	vec3 seam_col = color * (0.35 + 1.8 * burst + 0.6 * (1.0 - lids));
	out_col.rgb = mix(out_col.rgb, seam_col, clamp(seam * (1.0 - out_col.a * 0.6), 0.0, 1.0));
	out_col.a = max(out_col.a, clamp(seam, 0.0, 1.0));
	return out_col;
}

// The bangs: tapered strands hanging from above the frame. x = cover, y = rim.
vec2 strands(vec2 p) {
	float cover = 0.0;
	float rim = 0.0;
	float half_w = aspect * 0.5;
	for (int i = 0; i < STRANDS; i++) {
		float fi = float(i);
		float k = (fi + 0.5) / float(STRANDS);
		float side = k < 0.5 ? -1.0 : 1.0;
		vec2 root = vec2(mix(-0.9, 0.9, k) * half_w + (hash(fi) - 0.5) * 0.06, -0.72);
		float len = 0.84 + hash(fi + 7.0) * 0.26;
		// Hanging, leaning a little inward; swept out and up as `hair` rises.
		float sway = sin(TIME * 6.0 + fi * 1.7) * 0.02 * (1.0 - hair);
		float ang = -side * 0.12 + sway + side * hair * (1.25 + hash(fi + 3.0) * 0.5);
		vec2 dir = vec2(sin(ang), cos(ang));
		vec2 perp = vec2(dir.y, -dir.x);
		vec2 d = p - root;
		float u = dot(d, dir) / len;
		if (u < 0.0 || u > 1.0) {
			continue;
		}
		float bend = (0.05 + 0.2 * hair) * side * u * u;
		float v = dot(d, perp) - bend;
		// A lock: full at the root, tapering to a point.
		float w = mix(0.115, 0.003, pow(u, 1.7)) * (0.8 + hash(fi + 11.0) * 0.5);
		float body = 1.0 - smoothstep(w * 0.8, w, abs(v));
		float edge = body * smoothstep(w * 0.45, w, abs(v));
		cover = max(cover, body);
		rim = max(rim, edge * (0.3 + 0.7 * u));
	}
	return vec2(cover, rim);
}

void fragment() {
	vec2 p = (UV - 0.5) * vec2(aspect, 1.0);
	// A breath of the eye art's colour round the eyes as the power rises.
	float ax = abs(p.x);
	vec2 e = vec2(ax, p.y);
	float halo = exp(-dot(e - EYE, e - EYE) * 9.0) * (0.04 + 0.25 * intensity + 0.4 * burst);
	vec3 col = color * halo;
	// Speed lines bursting out from between the eyes.
	float ang = atan(p.y, p.x);
	float ray_id = floor(ang * 38.0);
	float line = step(0.82, hash(ray_id)) * smoothstep(0.25, 0.9, length(p)) * burst;
	col += color * line * 0.6;
	// Both eyes, the left one mirrored.
	vec4 eyes = eye(vec2(ax, p.y));
	col = mix(col, eyes.rgb, eyes.a);
	// The bangs in front: near-black, rim-lit in the eye art's colour.
	vec2 s = strands(p);
	col = mix(col, vec3(0.015, 0.012, 0.018), s.x);
	col += color * s.y * (0.35 + 0.8 * burst);
	// Vignette.
	col *= 1.0 - smoothstep(0.55, 1.1, length(p * vec2(0.75, 1.0)));
	COLOR = vec4(col, fade);
}
