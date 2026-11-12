shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never;
uniform float effect_time = 0.0;
uniform float strength = 1.0;
void fragment() {
	float edge = smoothstep(0.0, 0.18, UV.x) * smoothstep(0.0, 0.18, 1.0 - UV.x);
	float streak = pow(0.5 + 0.5 * sin(UV.y * 48.0 - effect_time * 5.5 + sin(UV.x * 21.0)), 8.0);
	float fade = 1.0 - smoothstep(0.72, 1.0, UV.y);
	ALBEDO = mix(vec3(0.46, 0.73, 0.77), vec3(0.90, 0.99, 0.92), 0.40 + streak * 0.40);
	ALPHA = edge * fade * (0.40 + streak * 0.24) * strength;
}
