shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never;

uniform sampler2D water_paint : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 water_tint : source_color = vec4(0.64, 0.8, 0.8, 0.32);
uniform float effect_time = 0.0;

void fragment() {
	float border = min(min(UV.x, 1.0 - UV.x), min(UV.y, 1.0 - UV.y));
	float feather = smoothstep(0.0, 0.16, border);
	vec2 drift = vec2(sin(UV.y * 18.0 + effect_time * 0.7), cos(UV.x * 15.0 - effect_time * 0.6)) * 0.005;
	vec3 paint = texture(water_paint, UV * 3.0 + drift).rgb;
	ALBEDO = mix(water_tint.rgb, paint, 0.35);
	float ripple = pow(0.5 + 0.5 * sin(UV.x * 65.0 + UV.y * 31.0 - effect_time * 1.2), 18.0);
	ALBEDO += vec3(0.055) * ripple;
	ALPHA = water_tint.a * feather;
}
