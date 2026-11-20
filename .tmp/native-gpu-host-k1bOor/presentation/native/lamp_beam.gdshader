shader_type spatial;
render_mode unshaded, cull_back, blend_add, depth_draw_never;

uniform vec4 tint : source_color = vec4(1.0, 0.81, 0.40, 0.18);
uniform float segment_length = 1.0;
uniform float head_fade = 0.0;
uniform float tail_fade = 0.0;
uniform float softness = 1.5;
varying float along;
varying vec3 beam_axis_view;

void vertex() {
	along = clamp(VERTEX.y / segment_length + 0.5, 0.0, 1.0);
	beam_axis_view = normalize((MODELVIEW_MATRIX * vec4(0.0,1.0,0.0,0.0)).xyz);
}

void fragment() {
	vec3 radial = normalize(VIEW - beam_axis_view * dot(VIEW,beam_axis_view));
	float facing = max(dot(normalize(NORMAL),radial),0.0);
	float density = pow(facing,softness);
	float ends = 1.0;
	if (head_fade > 0.0) ends *= smoothstep(0.0,head_fade,along);
	if (tail_fade > 0.0) ends *= smoothstep(0.0,tail_fade,1.0-along);
	ALBEDO = mix(tint.rgb,vec3(1.0,0.96,0.76),pow(facing,5.0)*.45);
	ALPHA = tint.a * density * ends;
}
