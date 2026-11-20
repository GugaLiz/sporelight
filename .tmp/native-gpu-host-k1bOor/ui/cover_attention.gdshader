shader_type canvas_item;
// A small continuous head response on a whole painted pose. The shoulders,
// hands and registered feet retain their source positions; no extra face layer.
uniform vec2 neck = vec2(0.5, 0.65);
uniform float head_angle = 0.0;
varying vec4 sprite_tint;
void vertex() {
	sprite_tint = COLOR;
}
void fragment() {
	float weight = 1.0 - smoothstep(neck.y - 0.025, neck.y + 0.035, UV.y);
	float angle = head_angle * weight;
	vec2 relative = UV - neck;
	vec2 sample_uv = neck + vec2(cos(angle) * relative.x + sin(angle) * relative.y,
		-sin(angle) * relative.x + cos(angle) * relative.y);
	COLOR = texture(TEXTURE, sample_uv) * sprite_tint;
}
