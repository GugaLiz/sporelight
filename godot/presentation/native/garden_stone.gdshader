shader_type spatial;
render_mode cull_disabled;

uniform vec4 stone : source_color = vec4(0.68, 0.72, 0.61, 1.0);
uniform vec4 grout : source_color = vec4(0.35, 0.43, 0.35, 1.0);
uniform bool wall = false;
uniform bool living = false;
uniform bool ramp = false;
varying vec3 world_at;
varying vec3 world_normal;

void vertex() {
	world_at = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}

float hash21(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

void fragment() {
	vec2 p = world_at.xz * 2.0;
	if (wall) {
		float horizontal = abs(world_normal.x) > 0.5 ? world_at.z : world_at.x;
		p = vec2(horizontal * 1.5, world_at.y * 3.0);
	}
	p.x += mod(floor(p.y), 2.0) * 0.5;
	vec2 cell = floor(p);
	vec2 edge = min(fract(p), 1.0 - fract(p));
	float joint = 1.0 - smoothstep(0.012, 0.027, min(edge.x, edge.y));
	if (ramp) joint = 1.0 - smoothstep(0.012, 0.027, edge.x);
	float bevel = 1.0 - smoothstep(0.027, 0.065, min(edge.x, edge.y));
	vec3 base = stone.rgb * (0.94 + hash21(cell) * 0.12);
	base += bevel * 0.025;
	// Distinguish true horizontal treads from their bevelled risers even
	// with decorative lighting turned off or on low-end Web renderers.
	if (ramp) base *= 0.80;
	if (living) base = mix(base, vec3(0.37, 0.49, 0.25), 0.35);
	ALBEDO = mix(base, grout.rgb, joint * 0.65);
	ROUGHNESS = 0.93;
}
