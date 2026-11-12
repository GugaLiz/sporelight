shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;
uniform vec4 tint : source_color = vec4(1.0);
uniform sampler2D grass : source_color, filter_linear_mipmap, repeat_enable;
uniform bool use_grass = false;
uniform bool inner_only = false;
void fragment() {
	vec3 paint = tint.rgb;
	if (use_grass) paint = mix(paint, texture(grass, vec2(UV.x, UV.y)).rgb, .35);
	float edge = min(UV.y, 1.0-UV.y);
	ALBEDO = paint;
	ALPHA = tint.a * smoothstep(0.0, .10, edge);
	if (inner_only) ALPHA *= smoothstep(.49,.51,UV.y);
}
