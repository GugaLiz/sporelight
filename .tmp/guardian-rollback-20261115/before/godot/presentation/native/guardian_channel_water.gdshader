shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled;
uniform float effect_time = 0.0;
uniform float flow_speed = 0.0;
uniform bool pool_surface = false;
uniform vec4 deep_color : source_color = vec4(0.27, 0.45, 0.46, 1.0);
uniform vec4 shallow_color : source_color = vec4(0.52, 0.68, 0.64, 1.0);
void fragment() {
	vec2 p = UV;
	float radial = length(p - vec2(0.48, 0.62));
	float phase = pool_surface ? radial * 36.0 - effect_time * 1.35 : p.y * 16.0 - effect_time * flow_speed * 10.0;
	float wave = sin(phase + sin(p.x * 9.0) * (pool_surface ? 0.10 : 0.30));
	float small_wave = sin(p.x * 21.0 + p.y * 12.0 + effect_time * 0.41);
	float ripple = wave * 0.08 + small_wave * 0.035;
	float edge = smoothstep(0.0, 0.12, p.x) * smoothstep(0.0, 0.12, 1.0-p.x);
	float glint = smoothstep(0.73, 0.97, wave) * (0.55 + small_wave * 0.20);
	if (pool_surface) glint *= smoothstep(0.02, 0.12, radial) * (1.0-smoothstep(0.36, 0.58, radial));
	ALBEDO = mix(deep_color.rgb, shallow_color.rgb, 0.39 + ripple + (1.0-edge)*0.09);
	ALBEDO = mix(ALBEDO, vec3(0.76,0.83,0.74), glint*0.34);
	EMISSION = vec3(0.66,0.76,0.69)*glint*0.025;
	ROUGHNESS = 0.28 + ripple;
	METALLIC = 0.05;
	SPECULAR = 0.42;
	ALPHA = 0.91;
}
