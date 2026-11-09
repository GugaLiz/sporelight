shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never;

uniform sampler2D water_paint : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 water_tint : source_color = vec4(0.64, 0.8, 0.8, 0.32);

void fragment() {
	float border = min(min(UV.x, 1.0 - UV.x), min(UV.y, 1.0 - UV.y));
	float feather = smoothstep(0.0, 0.16, border);
	vec3 paint = texture(water_paint, UV * 3.0).rgb;
	ALBEDO = mix(water_tint.rgb, paint, 0.35);
	ALPHA = water_tint.a * feather;
}
