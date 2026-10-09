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

#include "res://assets/shaders/eye_patterns.gdshaderinc"

void vertex() {
	// The same triangles as the iris: draw a hair in front of them (toward
	// the camera) so the two don't fight over depth.
	vec4 view = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	POSITION = PROJECTION_MATRIX * vec4(view.xyz * 0.9993, 1.0);
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
