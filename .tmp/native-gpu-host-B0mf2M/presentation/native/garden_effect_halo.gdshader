shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never;
uniform vec4 tint : source_color = vec4(1.0, 0.80, 0.30, 0.55);
uniform float phase = 0.0;
uniform float strength = 1.0;
uniform bool star = false;
uniform float ring_strength = 1.0;
uniform float glow_strength = 1.0;
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float ring = (1.0 - smoothstep(0.035, 0.11, abs(r - 0.63))) * 0.65;
	float glow = (1.0 - smoothstep(0.0, 1.0, r)) * 0.23;
	float cross = pow(max(0.0, 1.0 - abs(p.x)), 18.0) * (1.0 - abs(p.y));
	cross += pow(max(0.0, 1.0 - abs(p.y)), 18.0) * (1.0 - abs(p.x));
	ALBEDO = tint.rgb;
	ALPHA = clamp(star ? cross : ring * ring_strength + glow * glow_strength, 0.0, 1.0) * tint.a * strength * (0.91 + 0.09 * sin(phase));
}
