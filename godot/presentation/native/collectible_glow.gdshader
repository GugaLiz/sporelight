shader_type spatial;
// Light adds colour; an alpha-mixed ring could darken its own translucent rim.
render_mode unshaded, cull_disabled, blend_add, depth_draw_never, fog_disabled;
uniform float phase = 0.0;
void fragment() {
	float r = length(UV * 2.0 - 1.0);
	ALBEDO = vec3(1.0, 0.64, 0.14);
	ALPHA = pow(max(0.0, 1.0 - r), 2.0) * 0.24 * (0.93 + 0.07 * sin(phase));
}
