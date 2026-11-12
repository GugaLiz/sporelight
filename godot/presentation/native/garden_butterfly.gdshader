shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never;
uniform vec4 tint : source_color = vec4(0.98, 0.87, 0.67, 1.0);
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float upper = length((p - vec2(0.35, -0.35)) / vec2(0.57, 0.65));
	float lower = length((p - vec2(0.22, 0.39)) / vec2(0.43, 0.42));
	float shape = min(upper, lower);
	float edge = smoothstep(0.65, 1.0, shape);
	ALBEDO = mix(tint.rgb, vec3(0.55, 0.45, 0.32), edge * 0.6);
	ALPHA = (1.0 - smoothstep(0.92, 1.0, shape)) * tint.a;
}
