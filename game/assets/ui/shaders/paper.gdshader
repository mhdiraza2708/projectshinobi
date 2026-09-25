// Washi/parchment panel with fibre grain and torn, darkened edges.
shader_type canvas_item;
#include "res://assets/ui/shaders/ink_common.gdshaderinc"

uniform vec4 paper_color : source_color = vec4(0.937, 0.902, 0.824, 1.0);
uniform vec4 edge_color : source_color = vec4(0.56, 0.44, 0.30, 1.0);
uniform float opacity : hint_range(0.0, 1.0) = 0.95;
uniform float tear : hint_range(0.0, 20.0) = 7.0;
uniform vec2 rect_size = vec2(400.0, 120.0);
uniform float seed = 0.0;

void fragment() {
	vec2 px = UV * rect_size;
	float grain = ink_fbm(px * 0.03 + seed) * 0.6 + ink_fbm(px * 0.25 + seed * 3.1) * 0.25;
	float fibres = ink_noise(vec2(px.x * 0.05, px.y * 0.22) + seed * 1.7) * 0.03;
	vec3 col = paper_color.rgb * (0.9 + grain * 0.18 - fibres);

	float d = min(min(px.x, rect_size.x - px.x), min(px.y, rect_size.y - px.y));
	float rough = ink_fbm(px * 0.07 + seed * 7.0) * tear;
	col = mix(edge_color.rgb, col, smoothstep(0.0, 18.0, d - rough * 0.5));
	float alpha = opacity * smoothstep(0.0, 2.0, d - rough * 0.45 + 2.0);
	COLOR = vec4(col, alpha);
}
