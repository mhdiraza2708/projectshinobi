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
// The sky's colour grade: `tint` over all of it, and `horizon_tint` on top
// near the horizon, easing off by about 35 degrees up (golden hour's warm
// haze with a cooler sky overhead). `flash` lets lightning light the clouds.
uniform vec3 tint = vec3(1.0);
uniform vec3 horizon_tint = vec3(1.0);
uniform float flash = 0.0;
// How far the sun's wide halo reaches (a low, warm sun glows more).
uniform float sun_halo = 0.12;
// The photo's sun height and the game's sun height (radians). A sun lower
// than the photographed one squeezes the sky below it down toward the
// horizon (the horizon and the zenith stay put), so the drawn sun, the
// clouds around it and the light all agree. Equal heights leave it as shot.
uniform vec2 elevations = vec2(0.0);
// A time of day changing (the open world's clock): the previous sky fades
// out as this one fades in (blend 0 = all previous, 1 = all this one).
uniform sampler2D prev_panorama : source_color, filter_linear_mipmap, repeat_enable;
uniform float prev_scale = 1.0;
uniform mat3 prev_to_panorama = mat3(1.0);
uniform vec3 prev_tint = vec3(1.0);
uniform vec3 prev_horizon_tint = vec3(1.0);
uniform vec2 prev_elevations = vec2(0.0);
uniform float blend = 1.0;

vec2 panorama_uv(vec3 d) {
	return vec2(atan(d.x, -d.z) / TAU + 0.5, acos(clamp(d.y, -1.0, 1.0)) / PI);
}

// The direction `d` with the sky below the sun squeezed (or stretched) so
// the photo's sun at elevations.x appears at elevations.y.
vec3 lift_sun(vec3 d, vec2 elev) {
	if (elev.y < 0.01 || abs(elev.x - elev.y) < 0.001 || d.y <= 0.0) {
		return d;
	}
	float el = asin(min(d.y, 1.0));
	float e = el < elev.y ? el * (elev.x / elev.y)
		: elev.x + (el - elev.y) * ((1.5707963 - elev.x) / (1.5707963 - elev.y));
	vec2 h = d.xz / max(length(d.xz), 1e-5);
	return vec3(h.x * cos(e), sin(e), h.y * cos(e));
}

vec3 grade(vec3 eye, vec3 all, vec3 low) {
	return all * mix(low, vec3(1.0), smoothstep(0.0, 0.6, eye.y));
}

// One panorama's colour toward `eye` (EYEDIR, which only sky() can read),
// turned by `turn`.
vec3 sample_sky(sampler2D tex, mat3 turn, vec3 eye, bool cubemap) {
	vec2 uv = panorama_uv(normalize(turn * eye));
	if (cubemap) {
		// Reflections and ambient light: a blurred lookup is all they need.
		return textureLod(tex, uv, 4.0).rgb;
	}
	// No seam where the panorama wraps: take derivatives from whichever of
	// two wrap points is further from this pixel.
	vec2 uv2 = vec2(fract(uv.x + 0.5) - 0.5, uv.y);
	vec2 dx = dFdx(uv);
	vec2 dy = dFdy(uv);
	vec2 dx2 = dFdx(uv2);
	vec2 dy2 = dFdy(uv2);
	if (dot(dx2, dx2) + dot(dy2, dy2) < dot(dx, dx) + dot(dy, dy)) {
		dx = dx2;
		dy = dy2;
	}
	return textureGrad(tex, uv, dx, dy).rgb;
}

void sky() {
	vec3 col = sample_sky(panorama, to_panorama, lift_sun(EYEDIR, elevations), AT_CUBEMAP_PASS)
		* scale * grade(EYEDIR, tint, horizon_tint);
	if (blend < 0.999) {
		// Each sky keeps its own grade while they fade (no warm tint on the old sky).
		vec3 old = sample_sky(prev_panorama, prev_to_panorama, lift_sun(EYEDIR, prev_elevations), AT_CUBEMAP_PASS)
			* prev_scale * grade(EYEDIR, prev_tint, prev_horizon_tint);
		col = mix(old, col, blend);
	}
	col += flash * vec3(0.55, 0.6, 0.75) * smoothstep(-0.05, 0.4, EYEDIR.y);
	if (!AT_CUBEMAP_PASS) {
		float c = dot(EYEDIR, sun_direction);
		float a = acos(clamp(c, -1.0, 1.0));
		// Disc, then a tight glow and a wide halo (bloom spreads them more).
		col += sun_color * (smoothstep(sun_radius, sun_radius * 0.6, a) * 40.0
			+ exp(-a / (sun_radius * 3.0)) * 2.0 + exp(-a * 9.0) * sun_halo) * blend;
	}
	COLOR = col;
}
