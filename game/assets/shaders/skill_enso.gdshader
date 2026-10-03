shader_type spatial;
// The brush circle (enso) behind the character on the skill screen: a ragged
// ink ring that glows in the tree's colour, drawn with an unfinished gap the
// way a brushed enso is, slowly turning.
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;

uniform sampler2D noise : filter_linear_mipmap, repeat_enable;
uniform vec4 color : source_color = vec4(0.8, 0.3, 0.2, 1.0);
uniform float energy = 2.0;
uniform float radius = 0.4;
uniform float width = 0.055;
uniform float spin = 0.05;

void fragment() {
	vec2 p = UV - vec2(0.5);
	float r = length(p);
	float a = atan(p.y, p.x) + TIME * spin;
	float t = fract(a / 6.28318);
	// The brush thins and breaks at the end of its stroke.
	float stroke = smoothstep(0.0, 0.08, t) * (1.0 - smoothstep(0.86, 0.97, t));
	float wobble = (texture(noise, vec2(t * 3.0, 0.3)).r - 0.5) * 0.03;
	float w = width * (0.45 + 0.75 * stroke);
	float ring = 1.0 - smoothstep(w * 0.55, w, abs(r - radius - wobble));
	// Dry-brush streaks along the stroke.
	float dry = texture(noise, vec2(t * 9.0, r * 14.0)).r;
	ring *= smoothstep(0.22, 0.55, dry + stroke * 0.35);
	// A soft halo around it.
	float halo = exp(-pow((r - radius) / (width * 3.5), 2.0)) * 0.18 * stroke;
	float v = ring * stroke + halo;
	ALBEDO = color.rgb * energy;
	ALPHA = clamp(v, 0.0, 1.0);
}
