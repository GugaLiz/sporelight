shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never;

// A soft contact patch on the actual floor, not a projected light shadow.
uniform float strength = 0.18;
uniform bool square_footprint = false;

void fragment() {
	vec2 point = abs(UV * 2.0 - 1.0);
	float distance_to_center = square_footprint ? max(point.x, point.y) : length(point);
	ALBEDO = vec3(0.12, 0.13, 0.07);
	ALPHA = (1.0 - smoothstep(0.30, 1.0, distance_to_center)) * strength;
}
