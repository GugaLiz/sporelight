shader_type spatial;
render_mode unshaded, cull_back;

uniform vec4 tint : source_color = vec4(0.98, 0.86, 0.63, 1.0);
uniform float head_fade = 0.0;
uniform float tail_fade = 0.0;
uniform float segment_length = 1.0;
varying vec3 beam_axis_view;

void vertex() {
	beam_axis_view = normalize((MODELVIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
	// Taper only the exposed source/tail. Internal cell joins retain their
	// full radius, with no end discs or per-cell brightness reset.
	float envelope = 1.0;
	float along = clamp(VERTEX.y / segment_length + 0.5, 0.0, 1.0);
	if (head_fade > 0.0) envelope *= smoothstep(0.0, head_fade, along);
	if (tail_fade > 0.0) envelope *= smoothstep(0.0, tail_fade, 1.0 - along);
	VERTEX.xz *= mix(0.08, 1.0, envelope);
}

void fragment() {
	// The actual cylinder normal produces a white centre and warm round sides.
	// No ALPHA output: the body must stay distinct from the floor underneath.
	vec3 radial_view = normalize(VIEW - beam_axis_view * dot(VIEW, beam_axis_view));
	float facing = pow(max(dot(normalize(NORMAL), radial_view), 0.0), 4.0);
	vec3 light_color = mix(tint.rgb, vec3(1.0, 0.96, 0.84), facing);
	ALBEDO = light_color;
	EMISSION = light_color * 0.035;
}
