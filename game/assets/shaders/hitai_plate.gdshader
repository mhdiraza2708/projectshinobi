shader_type spatial;
// The steel plate of a forehead protector: brushed metal, a bevelled rim
// that catches the light on top, a rivet in each corner and an engraved
// emblem (an original "ember" mark: a flame over a hearth line with two
// sparks). UV: x across the plate, y top to bottom; the rim faces use the
// edge of the UV square.
render_mode diffuse_toon, specular_toon;

uniform vec4 steel : source_color = vec4(0.66, 0.69, 0.74, 1.0);
uniform vec4 engraving : source_color = vec4(0.2, 0.21, 0.24, 1.0);
// Plate width / height, so round things stay round.
uniform float aspect = 3.2;
uniform float emblem = 1.0;

// iq's uneven capsule: circle r1 at the origin, r2 at height h (y up).
float uneven_capsule(vec2 p, float r1, float r2, float h) {
	p.x = abs(p.x);
	float b = (r1 - r2) / h;
	float a = sqrt(1.0 - b * b);
	float k = dot(p, vec2(-b, a));
	if (k < 0.0) return length(p) - r1;
	if (k > a * h) return length(p - vec2(0.0, h)) - r2;
	return dot(p, vec2(a, b)) - r1;
}

float box(vec2 p, vec2 half_size) {
	vec2 d = abs(p) - half_size;
	return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

// Signed distance to the emblem, in plate heights (y up, centred).
float ember(vec2 p) {
	p /= 1.3;
	// The flame's tip leans over, like a flame caught by a breeze.
	vec2 f = p - vec2(-0.02, -0.1);
	f.x -= 1.1 * max(f.y, 0.0) * max(f.y, 0.0);
	float flame = uneven_capsule(f, 0.13, 0.01, 0.34);
	// Hollow it: an inner tongue of bare metal, leaning with the flame.
	vec2 g = p - vec2(-0.015, -0.08);
	g.x -= 1.2 * max(g.y, 0.0) * max(g.y, 0.0);
	float inner = uneven_capsule(g, 0.05, 0.004, 0.16);
	flame = max(flame, -inner);
	float hearth = box(p - vec2(0.0, -0.23), vec2(0.3, 0.03));
	float spark_l = length(p - vec2(-0.24, 0.02)) - 0.035;
	float spark_r = length(p - vec2(0.25, 0.16)) - 0.028;
	return min(min(flame, hearth), min(spark_l, spark_r)) * 1.3;
}

void fragment() {
	vec2 uv = UV;
	vec2 p = vec2((uv.x - 0.5) * aspect, 0.5 - uv.y);

	// Brushed steel: fine horizontal streaks, a little darker toward the bottom.
	float streak = fract(sin(floor(uv.y * 160.0) * 91.7) * 4375.5);
	vec3 col = steel.rgb * (0.9 + 0.08 * streak + 0.14 * (0.5 - uv.y));

	// Bevel: bright along the top edge, shadowed along the bottom.
	float ex = min(uv.x, 1.0 - uv.x) * aspect;
	float ey = min(uv.y, 1.0 - uv.y);
	float bevel = 1.0 - smoothstep(0.0, 0.09, min(ex, ey));
	float top = step(uv.y, 0.5);
	col = mix(col, col * 1.3 + vec3(0.06), bevel * top);
	col = mix(col, col * 0.55, bevel * (1.0 - top) * 0.8);
	// A dark seam where the bevel meets the face.
	col *= 1.0 - 0.35 * (smoothstep(0.07, 0.09, min(ex, ey)) - smoothstep(0.09, 0.11, min(ex, ey)));

	// Rivets.
	vec2 q = abs(p) - vec2(aspect * 0.5 - 0.17, 0.5 - 0.18);
	float rd = length(q);
	float rivet = 1.0 - smoothstep(0.045, 0.058, rd);
	float shine = clamp(0.6 + q.y * 8.0 - q.x * 4.0, 0.0, 1.0);
	col = mix(col, mix(steel.rgb * 0.5, steel.rgb * 1.45, shine), rivet);
	col *= 1.0 - 0.4 * (smoothstep(0.055, 0.062, rd) - smoothstep(0.062, 0.075, rd));

	// Engraving: a cut into the metal, dark inside, with a lit lower wall.
	if (emblem > 0.5) {
		float d = ember(p);
		float inside = 1.0 - smoothstep(-0.004, 0.004, d);
		float wall = (1.0 - smoothstep(0.0, 0.018, abs(d + 0.012))) * inside;
		col = mix(col, engraving.rgb, inside * 0.85);
		// Light comes from above: the lower inner wall of the cut catches it.
		float lower = clamp(-dFdy(d) * 400.0, 0.0, 1.0);
		col = mix(col, steel.rgb * 1.2, wall * 0.5);
		col = mix(col, col * 1.15, lower * inside * 0.3);
	}

	ALBEDO = col;
	METALLIC = 0.35;
	ROUGHNESS = 0.32;
	SPECULAR = 0.7;
	RIM = 0.25;
	RIM_TINT = 0.6;
}
