shader_type spatial;
render_mode unshaded, cull_disabled;
uniform sampler2D grass : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 tint : source_color = vec4(.65,.74,.57,1.0);
void fragment() {
	float light = .04 * (1.0 - UV.y);
	vec3 base = tint.rgb + vec3(light);
	ALBEDO = mix(base, texture(grass, UV).rgb, .35);
	ROUGHNESS = 1.0;
}
