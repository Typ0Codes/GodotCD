shader_type canvas_item;

uniform vec4 color_a : source_color;
uniform vec4 color_b : source_color;
uniform vec4 color_c : source_color;
uniform vec4 color_d : source_color;
uniform float shift : hint_range(0.0, 1.0) = 0.0;
uniform float time = 0.0;

void fragment() {
	vec2 uv = UV;

	// Slowly undulating blend weights
	float wave1 = sin(uv.x * 2.5 + time * 0.7 + shift * 6.28) * 0.5 + 0.5;
	float wave2 = cos(uv.y * 2.0 + time * 0.5) * 0.5 + 0.5;
	float wave3 = sin((uv.x + uv.y) * 1.8 + time * 0.3) * 0.5 + 0.5;

	vec4 col = mix(color_a, color_b, wave1);
	col = mix(col, color_c, wave2 * 0.6);
	col = mix(col, color_d, wave3 * 0.4);

	COLOR = col;
}