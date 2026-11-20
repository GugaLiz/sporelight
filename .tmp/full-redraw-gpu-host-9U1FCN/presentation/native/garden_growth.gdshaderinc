// Local coordinates are shared by all faces of a connector; no texture stretch.
uniform float growth_progress = 1.0;
uniform vec3 growth_axis = vec3(0.0, 0.0, 1.0);
uniform bool growth_glow = true;
varying float growth_distance;

bool growth_hidden() {
	return growth_progress < 1.0 && (growth_progress <= 0.0 || growth_distance > growth_progress);
}

vec3 growth_light() {
	float band = 1.0 - smoothstep(0.0, 0.10, max(0.0, growth_progress - growth_distance));
	return growth_glow && growth_progress > 0.0 && growth_progress < 1.0 ? vec3(0.28, 0.22, 0.09) * band : vec3(0.0);
}
