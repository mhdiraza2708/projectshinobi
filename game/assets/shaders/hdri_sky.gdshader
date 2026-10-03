shader_type sky;
// A photographed sky (a Poly Haven pure-sky HDRI, packed by
// art/polyhaven/fetch.py into an 8-bit panorama): `scale` brings back the
// photo's light levels, the panorama turns so the sun in the photo sits
// where the game's sun is, and the sun's disc and glow are drawn on top
// (the 8-bit image clips them). Reflections and ambient light get the same
// sky without the sun (the DirectionalLight already lights the world).

uniform sampler2D panorama : source_color, filter_linear_mipmap, repeat_enable;
// The light level of a white texel, times the mood's brightness.
uniform float scale = 1.0;
// Turns world directions into the panorama's (the inverse of the turn).
uniform mat3 to_panorama = mat3(1.0);
// Toward the sun (or moon) in the world, its colour (already times its
// brightness) and its angular radius in radians.
uniform vec3 sun_direction = vec3(0.0, 1.0, 0.0);
uniform vec3 sun_color = vec3(1.0);
uniform float sun_radius = 0.0045;
// Darkens toward a storm's grey and lets lightning light the clouds.
uniform vec3 tint = vec3(1.0);
uniform float flash = 0.0;

vec2 panorama_uv(vec3 d) {
	return vec2(atan(d.x, -d.z) / TAU + 0.5, acos(clamp(d.y, -1.0, 1.0)) / PI);
}

void sky() {
	vec3 d = normalize(to_panorama * EYEDIR);
	vec2 uv = panorama_uv(d);
	vec3 col;
	if (AT_CUBEMAP_PASS) {
		// Reflections and ambient light: a blurred lookup is all they need.
		col = textureLod(panorama, uv, 4.0).rgb;
	} else {
		// No seam where the panorama wraps: take derivatives from whichever
		// of two wrap points is further from this pixel.
		vec2 uv2 = vec2(fract(uv.x + 0.5) - 0.5, uv.y);
		vec2 dx = dFdx(uv);
		vec2 dy = dFdy(uv);
		vec2 dx2 = dFdx(uv2);
		vec2 dy2 = dFdy(uv2);
		if (dot(dx2, dx2) + dot(dy2, dy2) < dot(dx, dx) + dot(dy, dy)) {
			dx = dx2;
			dy = dy2;
		}
		col = textureGrad(panorama, uv, dx, dy).rgb;
	}
	col *= scale * tint;
	col += flash * vec3(0.55, 0.6, 0.75) * smoothstep(-0.05, 0.4, EYEDIR.y);
	if (!AT_CUBEMAP_PASS) {
		float c = dot(EYEDIR, sun_direction);
		float a = acos(clamp(c, -1.0, 1.0));
		// Disc, then a tight glow and a wide halo (bloom spreads them more).
		col += sun_color * (smoothstep(sun_radius, sun_radius * 0.6, a) * 40.0
			+ exp(-a / (sun_radius * 3.0)) * 2.0 + exp(-a * 9.0) * 0.12);
	}
	COLOR = col;
}
