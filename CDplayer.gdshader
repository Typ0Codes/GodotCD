shader_type canvas_item;

uniform float inner_radius = 0.15;
uniform float outer_radius = 0.48;

void fragment() {
    float dist = distance(UV, vec2(0.5));

    if (dist < inner_radius || dist > outer_radius)
        COLOR = vec4(0.0);
    else
        COLOR = texture(TEXTURE, UV);
}