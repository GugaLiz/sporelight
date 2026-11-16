shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never;

uniform vec4 tint : source_color = vec4(1.0, 0.9, 0.6, 0.18);
uniform float head_fade = 0.0;
uniform float tail_fade = 0.0;
uniform bool contact = false;
uniform bool soft_volume = false;
uniform float emission_strength = 0.18;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float strength;
	if (contact) {
		strength = pow(max(0.0, 1.0 - length(p)), 2.0);
	} else {
		if (soft_volume) {
			// A round cross-section has more visible light through its centre.
			// Keep that broad density, then feather the outer boundary away.
			float radius = abs(p.x);
			float density = pow(max(0.0, 1.0 - radius * radius), 0.75);
			strength = density * (1.0 - smoothstep(0.60, 1.0, radius));
		} else {
			strength = pow(1.0 - smoothstep(0.05, 1.0, abs(p.x)), 1.8);
		}
		// Quad UV.y is one at the segment's local -Y (source) edge.
		if (head_fade > 0.0) strength *= smoothstep(0.0, head_fade, 1.0 - UV.y);
		if (tail_fade > 0.0) strength *= smoothstep(0.0, tail_fade, UV.y);
	}
	ALBEDO = tint.rgb;
	EMISSION = tint.rgb * emission_strength;
	ALPHA = tint.a * strength;
}
