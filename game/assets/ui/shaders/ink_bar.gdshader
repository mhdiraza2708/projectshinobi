// A horizontal brush stroke that fills to `value`, with a lighter trail that
// catches up after damage (`trail`) and ragged dry-brush edges.
shader_type canvas_item;
#include "res://assets/ui/shaders/ink_common.gdshaderinc"

uniform vec4 ink_color : source_color = vec4(0.72, 0.13, 0.11, 1.0);
uniform vec4 trail_color : source_color = vec4(0.98, 0.86, 0.62, 1.0);
uniform vec4 back_color : source_color = vec4(0.10, 0.09, 0.11, 0.45);
uniform float value : hint_range(0.0, 1.0) = 1.0;
uniform float trail : hint_range(0.0, 1.0) = 1.0;
uniform vec2 rect_size = vec2(360.0, 24.0);
uniform float seed = 1.0;

void fragment() {
	vec2 px = UV * rect_size;
	float half_h = rect_size.y * 0.5;
	float dy = abs(px.y - half_h) / half_h;
	float ragged = ink_fbm(vec2(px.x * 0.045, seed + (px.y > half_h ? 5.0 : 0.0)));
	float body = 1.0 - smoothstep(0.62 + ragged * 0.3, 0.9 + ragged * 0.12, dy);
	// Taper both ends like a real stroke.
	float taper = smoothstep(0.0, 10.0, px.x) * smoothstep(0.0, 6.0, rect_size.x - px.x);
	body *= taper;

	float streak = ink_noise(vec2(px.x * 0.012, px.y * 0.75) + seed * 2.0);
	float tip = ink_fbm(vec2(px.y * 0.3, seed * 3.0)) * 9.0;
	float fill_end = value * rect_size.x;
	float in_fill = 1.0 - smoothstep(fill_end - tip - 3.0, fill_end - tip + 3.0, px.x);
	float in_trail = (1.0 - smoothstep(trail * rect_size.x - 3.0, trail * rect_size.x + 1.0, px.x)) * step(value, trail);

	vec4 c = vec4(back_color.rgb, back_color.a * body);
	c = mix(c, vec4(trail_color.rgb, body), in_trail * (1.0 - in_fill));
	vec3 ink = ink_color.rgb * (0.78 + streak * 0.4);
	c = mix(c, vec4(ink, body * (0.82 + streak * 0.18)), in_fill);
	COLOR = c;
}
