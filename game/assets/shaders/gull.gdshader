shader_type spatial;
// Gulls wheeling over the sea (Seabirds). Every bird of every flock is one
// instance of one little mesh, and the whole flight is worked out here, on
// the graphics card: the instance sits at the middle of its circle and
// INSTANCE_CUSTOM says how big the circle is, how fast the bird goes round
// it (negative: the other way), where in the circle it starts and how big
// the bird is. Nothing moves on the processor.
// The mesh faces +Z with its wings along X; vertex colour is the plumage.
render_mode cull_disabled, specular_disabled;

// 0: flying; 1: gone to roost (night), when the gulls are out of sight.
uniform float roost = 0.0;

void vertex() {
	vec4 c = INSTANCE_CUSTOM;
	float dir = c.y < 0.0 ? -1.0 : 1.0;
	float a = c.z + TIME * c.y;
	vec3 centre = vec3(cos(a), 0.0, sin(a)) * c.x;
	// Riding the air: a slow rise and fall.
	centre.y = sin(TIME * 0.45 + c.z * 3.1) * 1.8 + sin(TIME * 0.93 + c.z) * 0.4;
	vec2 tangent = dir * vec2(-sin(a), cos(a));

	// Short bursts of flapping between long glides on bowed wings.
	float burst = smoothstep(0.1, 0.55, sin(TIME * 0.33 + c.z * 7.0));
	float flap = sin(TIME * 7.5 + c.z * 11.0) * burst;
	vec3 v = VERTEX * c.w * (1.0 - roost);
	float span = abs(v.x);
	v.y += span * 0.1 + span * span * (0.1 * (1.0 - burst) + 0.36 * flap);

	// Lean into the turn: the wing toward the middle of the circle dips.
	float bank = 0.3 * dir;
	float cb = cos(bank);
	float sb = sin(bank);
	v = vec3(v.x * cb - v.y * sb, v.x * sb + v.y * cb, v.z);
	vec3 n = vec3(NORMAL.x * cb - NORMAL.y * sb, NORMAL.x * sb + NORMAL.y * cb, NORMAL.z);

	// Face the way it is flying.
	mat3 yaw = mat3(vec3(tangent.y, 0.0, -tangent.x), vec3(0.0, 1.0, 0.0), vec3(tangent.x, 0.0, tangent.y));
	VERTEX = yaw * v + centre;
	NORMAL = yaw * n;
}

void fragment() {
	ALBEDO = COLOR.rgb;
	// Pale from below too, where the sun never reaches.
	EMISSION = COLOR.rgb * 0.4;
	ROUGHNESS = 0.8;
}
