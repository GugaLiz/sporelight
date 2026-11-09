shader_type spatial;
render_mode cull_disabled;
#include "res://presentation/native/garden_growth.gdshaderinc"

uniform sampler2D original_stone : source_color, filter_linear_mipmap, repeat_disable;
uniform bool stair_side = false;

void vertex() {
	growth_distance = dot(VERTEX, growth_axis) + 0.5;
}

float stone_hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	if (growth_hidden()) discard;
	// UV is the unfolded vertical wall in world units. Build horizontal stone
	// courses here; the paving's painted overhead joints are not wall joints.
	vec2 at = UV * 4.5;
	vec2 block_size = stair_side ? vec2(0.36, 0.17) : vec2(0.48, 0.30);
	float row_y = at.y / block_size.y;
	float row = floor(row_y);
	float along = at.x / block_size.x + stone_hash(vec2(row, 4.0)) * 0.85;
	vec2 cell = vec2(floor(along), row);
	vec2 local = vec2(fract(along), fract(row_y));
	float seed = stone_hash(cell);
	// Only sample the interior of the original broad warm stone. This keeps
	// its painted grain without projecting grass or a second perspective.
	vec2 sample_uv = vec2(0.27, 0.35) + local * vec2(0.32, 0.34);
	vec3 stone = texture(original_stone, sample_uv).rgb;
	float wobble = sin(at.x * 31.0 + row * 2.7) * 0.0025;
	vec2 edge = min(local, vec2(1.0) - local) * block_size;
	float distance_to_joint = min(edge.x, edge.y + wobble);
	float joint = 1.0 - smoothstep(0.003, 0.010, distance_to_joint);
	float bevel = smoothstep(0.008, 0.024, distance_to_joint);
	vec3 face = stone * (0.85 + seed * 0.09) * mix(0.91, 1.0, bevel);
	ALBEDO = mix(face, stone * vec3(0.54, 0.55, 0.46), joint * 0.72);
	if (stair_side) {
		// A narrow stringer is dressed in long stones, not several courses of
		// wall bricks cut into tiny triangles by the diagonal top and bottom.
		float segment = at.x / 0.62;
		float part = floor(segment);
		float tone = stone_hash(vec2(part, 9.0));
		vec2 grain_at = vec2(fract(segment), fract(at.y * 0.65));
		vec2 crop = vec2(0.30, 0.39) + vec2(tone, 1.0 - tone) * 0.02;
		vec3 dressed = texture(original_stone, crop + grain_at * vec2(0.24, 0.23)).rgb;
		float distance = min(fract(segment), 1.0 - fract(segment));
		float seam = 1.0 - smoothstep(0.002, 0.002 + max(fwidth(segment), 0.003), distance);
		// Shade the stone nosing at a fixed physical thickness; the profile
		// comes from the mesh, so this reads on either side of the flight.
		float depth = UV2.y;
		float lip = depth < 0.0 ? 0.0 : 1.0 - smoothstep(0.018, 0.032, depth);
		float under_lip = depth < 0.0 ? 0.0 : smoothstep(0.025, 0.034, depth) * (1.0 - smoothstep(0.045, 0.070, depth));
		float shade = depth < 0.0 ? 0.68 : mix(0.77, 1.04, lip) - under_lip * 0.10;
		ALBEDO = dressed * shade * (0.96 + tone * 0.07) * (1.0 - seam * 0.10);
	}
	ROUGHNESS = 1.0;
	EMISSION = growth_light();
}
