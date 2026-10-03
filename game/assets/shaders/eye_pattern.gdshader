shader_type spatial;
// An eye art opened: an animated pattern drawn over a character's irises
// (a next pass on the iris material, so it shares the iris mesh and UVs).
// Each iris is found in UV space: its centre and radii come from the iris
// texture (EyePattern). Every pattern here is original to this project.
//
// pattern: 0 hawk (slit pupil, ring and feather marks; awakened: a burst of
//          straight rays), 1 mirror (two facing crescents; awakened: a
//          diamond pupil inside a hexagon), 2 seal (a ring of twelve marks;
//          awakened: a twelve-pointed star), 3 still (six lotus petals;
//          awakened: twelve, in two layers).
render_mode unshaded, blend_mix, depth_draw_never, cull_back, shadows_disabled;

uniform vec2 center_a = vec2(0.25, 0.5);
uniform vec2 center_b = vec2(0.75, 0.5);
// Iris radius in UV units (x, y): the texture is usually twice as wide as tall.
uniform vec2 radius = vec2(0.115, 0.255);
uniform int pattern = 0;
uniform vec3 color : source_color = vec3(0.9, 0.6, 0.2);
// 0 = closed (nothing drawn), 1 = fully open.
uniform float intensity : hint_range(0.0, 1.0) = 0.0;
// 0 = the eye art's first form, 1 = awakened.
uniform float awakened : hint_range(0.0, 1.0) = 0.0;
// Extra turn (radians) while the pattern spins into place.
uniform float spin = 0.0;
// How brightly the lines glow (above 1 blooms on the High preset).
uniform float glow = 1.6;

const float INK = 0.06;

void vertex() {
	// The same triangles as the iris: draw a hair in front of them (toward
	// the camera) so the two don't fight over depth.
	vec4 view = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	POSITION = PROJECTION_MATRIX * vec4(view.xyz * 0.9993, 1.0);
}


float band(float x, float centre, float half_width) {
	return 1.0 - smoothstep(half_width * 0.6, half_width, abs(x - centre));
}

// Distance from p to the segment a-b.
float segment(vec2 p, vec2 a, vec2 b) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
	return length(pa - ba * h);
}

// A straight tapered mark from radius r0 to r1 along angle ang.
float ray(vec2 p, float ang, float r0, float r1, float w0, float w1) {
	vec2 d = vec2(cos(ang), sin(ang));
	float along = dot(p, d);
	float across = abs(dot(p, vec2(-d.y, d.x)));
	float k = clamp((along - r0) / (r1 - r0), 0.0, 1.0);
	float w = mix(w0, w1, k);
	float inside = step(r0, along) * step(along, r1);
	return inside * (1.0 - smoothstep(w * 0.7, w, across));
}

float circle(vec2 p, vec2 c, float r, float soft) {
	return 1.0 - smoothstep(r - soft, r + soft, length(p - c));
}

// Lines (ink) and glow for each pattern; x = ink, y = glow.
vec2 hawk(vec2 p, float r, float a, float aw) {
	// A vertical slit pupil that narrows when awakened.
	float slit_w = mix(0.17, 0.09, aw) * sqrt(max(0.0, 1.0 - p.y * p.y / 0.42));
	float pupil = 1.0 - smoothstep(slit_w * 0.75, slit_w, abs(p.x));
	pupil *= step(abs(p.y), 0.64);
	float ring = band(r, 0.66, 0.055);
	float marks = 0.0;
	for (int i = 0; i < 4; i++) {
		float ang = PI * 0.25 + float(i) * PI * 0.5 + spin;
		marks = max(marks, ray(p, ang, 0.7, 0.95, 0.1, 0.025));
	}
	float rays = 0.0;
	for (int i = 0; i < 8; i++) {
		float ang = float(i) * PI * 0.25 + spin;
		rays = max(rays, ray(p, ang, 0.24, 0.97, 0.075, 0.015));
	}
	float ink = max(pupil, marks * (1.0 - aw));
	float lit = max(ring, rays * aw);
	return vec2(ink, lit);
}

vec2 mirror(vec2 p, float r, float a, float aw) {
	vec2 q = mat2(vec2(cos(spin), sin(spin)), vec2(-sin(spin), cos(spin))) * p;
	// Two crescents facing each other across the pupil: ( and ).
	float c1 = circle(q, vec2(-0.42, 0.0), 0.5, 0.02) * (1.0 - circle(q, vec2(-0.6, 0.0), 0.46, 0.02));
	float c2 = circle(q, vec2(0.42, 0.0), 0.5, 0.02) * (1.0 - circle(q, vec2(0.6, 0.0), 0.46, 0.02));
	float crescents = max(c1, c2) * step(r, 0.95);
	float pupil_round = circle(p, vec2(0.0), 0.2, 0.025);
	// Awakened: a diamond pupil and a hexagon around it.
	float diamond = 1.0 - smoothstep(0.2, 0.23, abs(q.x) + abs(q.y) * 0.7);
	float hex_r = 0.8 * cos(PI / 6.0) / cos(mod(a - spin + PI / 6.0, PI / 3.0) - PI / 6.0);
	float hex = band(r, hex_r, 0.045);
	float ink = max(crescents, mix(pupil_round, diamond, aw));
	return vec2(ink, hex * aw);
}

vec2 seal(vec2 p, float r, float a, float aw) {
	// Twelve marks round a ring (the twelve seals), alternating dot and bar,
	// turning slowly.
	float marks = 0.0;
	for (int i = 0; i < 12; i++) {
		float ang = float(i) * TAU / 12.0 + spin + TIME * 0.25;
		vec2 at = vec2(cos(ang), sin(ang)) * 0.72;
		if (i % 2 == 0) {
			marks = max(marks, circle(p, at, 0.09, 0.02));
		} else {
			vec2 t = vec2(-sin(ang), cos(ang));
			marks = max(marks, 1.0 - smoothstep(0.035, 0.055, segment(p, at - t * 0.09, at + t * 0.09)));
		}
	}
	float pupil = circle(p, vec2(0.0), 0.2, 0.025);
	// Awakened: a twelve-pointed star (every fifth point joined), turning
	// the other way.
	float star = 0.0;
	for (int i = 0; i < 12; i++) {
		float a0 = float(i) * TAU / 12.0 - spin * 1.5 - TIME * 0.4;
		float a1 = a0 + TAU * 5.0 / 12.0;
		star = max(star, 1.0 - smoothstep(0.018, 0.034, segment(p, vec2(cos(a0), sin(a0)) * 0.6, vec2(cos(a1), sin(a1)) * 0.6)));
	}
	float ink = max(marks, pupil);
	return vec2(ink, star * aw);
}

vec2 still(vec2 p, float r, float a, float aw) {
	// Lotus petals round the pupil: six, or twelve in two layers awakened.
	float rot = a - spin;
	float petals6 = 0.3 + 0.5 * pow(abs(cos(rot * 3.0)), 3.0);
	float petals12 = 0.3 + 0.55 * pow(abs(cos(rot * 6.0)), 3.0);
	float inner12 = 0.25 + 0.38 * pow(abs(cos(rot * 6.0 + PI * 0.5)), 3.0);
	float edge6 = band(r, petals6, 0.05);
	float edge12 = max(band(r, petals12, 0.04), band(r, inner12, 0.035));
	float pupil = circle(p, vec2(0.0), mix(0.17, 0.12, aw), 0.02);
	float edge = mix(edge6, edge12, aw);
	float ink = max(edge * (1.0 - aw), pupil);
	float core = circle(p, vec2(0.0), 0.3, 0.2) * aw * 0.5;
	return vec2(ink, edge * aw + core);
}

void fragment() {
	vec2 c = distance(UV / radius, center_a / radius) < distance(UV / radius, center_b / radius) ? center_a : center_b;
	vec2 p = (UV - c) / radius;
	// The second eye mirrors the first, so both patterns face the nose alike.
	if (c == center_b) {
		p.x = -p.x;
	}
	p.y = -p.y;
	float r = length(p);
	if (r > 1.02 || intensity <= 0.0) {
		discard;
	}
	float a = atan(p.y, p.x);
	vec2 m;
	if (pattern == 0) {
		m = hawk(p, r, a, awakened);
	} else if (pattern == 1) {
		m = mirror(p, r, a, awakened);
	} else if (pattern == 2) {
		m = seal(p, r, a, awakened);
	} else {
		m = still(p, r, a, awakened);
	}
	// The iris itself takes the eye art's colour, brighter toward the pupil,
	// with a dark rim; the pattern is inked over it and glows.
	float rim = smoothstep(0.82, 1.0, r);
	vec3 iris = color * mix(1.2, 0.6, r) * (1.0 - rim * 0.7);
	float lit = clamp(m.y, 0.0, 1.0);
	vec3 col = mix(iris, vec3(INK), m.x * (1.0 - lit));
	col = mix(col, color * (1.0 + glow), lit);
	float edge_fade = 1.0 - smoothstep(0.96, 1.02, r);
	ALBEDO = col;
	// The iris shows through between the lines.
	ALPHA = intensity * edge_fade * max(0.45, max(m.x, lit));
}
