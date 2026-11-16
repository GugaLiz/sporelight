shader_type spatial;
render_mode unshaded, cull_disabled;

uniform sampler2D mirror_paint : source_color, filter_linear_mipmap, repeat_enable;
varying vec3 glass_vertex;

void vertex() {
	glass_vertex = VERTEX;
}

void fragment() {
	// The actual +/-Z glass planes share a silver reflection treatment.
	// Position-based mapping avoids BoxMesh's atlas UVs and retains the real
	// ellipse on both faces, without billboarding or a leaf painted over it.
	vec2 oval = glass_vertex.xy / vec2(0.238, 0.21);
	if (dot(oval, oval) > 1.0) {
		discard;
	}
	vec2 pane_uv = glass_vertex.xy / vec2(0.53, 0.42) + vec2(0.5);
	vec3 sky = mix(vec3(0.43, 0.59, 0.60), vec3(0.93, 0.98, 0.98), smoothstep(0.15, 0.95, pane_uv.y));
	float horizon = exp(-pow((pane_uv.y - 0.43) / 0.085, 2.0));
	vec3 glass = mix(sky, vec3(0.64, 0.76, 0.74), horizon * 0.34);
	vec3 paint = texture(mirror_paint, pane_uv * 0.35).rgb;
	glass = mix(glass, paint, 0.035);
	float diagonal = pane_uv.x * 0.88 + pane_uv.y * 0.48;
	float glint = 1.0 - smoothstep(0.025, 0.075, abs(diagonal - 0.68));
	float echo = 1.0 - smoothstep(0.008, 0.022, abs(diagonal - 0.83));
	ALBEDO = mix(glass, vec3(0.99, 1.0, 0.98), glint * 0.72 + echo * 0.30);
}
