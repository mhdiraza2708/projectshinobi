// One bold brush stroke that sweeps in from the left (`progress` 0 -> 1).
shader_type canvas_item;
#include "res://assets/ui/shaders/ink_common.gdshaderinc"

uniform vec4 ink_color : source_color = vec4(0.07, 0.06, 0.08, 0.92);
uniform float progress : hint_range(0.0, 1.0) = 1.0;
uniform vec2 rect_size = vec2(900.0, 110.0);
uniform float seed = 4.0;

void fragment() {
	vec2 px = UV * rect_size;
	float half_h = rect_size.y * 0.5;
	// The stroke swells in the middle and thins at both ends.
	float thickness = mix(0.35, 0.95, pow(sin(UV.x * PI), 0.6));
	float ragged = ink_fbm(vec2(px.x * 0.02, seed + step(half_h, px.y) * 9.0));
	float dy = abs(px.y - half_h) / half_h;
	float body = 1.0 - smoothstep(thickness - 0.18 + ragged * 0.2, thickness + ragged * 0.1, dy);
	float streak = ink_noise(vec2(px.x * 0.008, px.y * 0.35) + seed);
	float front = progress * (rect_size.x + 80.0) - 40.0 + ink_fbm(vec2(px.y * 0.05, seed)) * 40.0;
	float revealed = 1.0 - smoothstep(front - 20.0, front + 20.0, px.x);
	COLOR = vec4(ink_color.rgb * (0.8 + streak * 0.35), ink_color.a * body * revealed * (0.85 + streak * 0.15));
}
