shader_type canvas_item;
render_mode unshaded;

uniform sampler2D next_pose : filter_linear, repeat_disable;
uniform float pose_weight : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec4 source = texture(TEXTURE, UV);
	vec4 target = texture(next_pose, UV);
	float alpha = mix(source.a, target.a, pose_weight);
	vec3 premultiplied = mix(source.rgb * source.a, target.rgb * target.a, pose_weight);
	COLOR = vec4(alpha > 0.0001 ? premultiplied / alpha : vec3(0.0), alpha);
}
