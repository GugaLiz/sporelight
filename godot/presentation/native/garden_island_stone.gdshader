shader_type spatial;
render_mode cull_disabled;
#include "res://presentation/native/garden_growth.gdshaderinc"

uniform sampler2D original_stone : source_color, filter_linear_mipmap, repeat_disable;
// Repeat the complete authored wall, including its mortar, chips and moss.
// This is distinct from original_stone, which dresses the narrow stair sides.
uniform sampler2D wall_art : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D wall_art_right : source_color, filter_linear_mipmap, repeat_enable;
uniform vec2 wall_pixels_per_unit = vec2(70.0, 73.846153846);
uniform vec4 wall_wash : source_color = vec4(0.70588, 0.72157, 0.58039, 1.0);
uniform vec4 wall_foot : source_color = vec4(0.2, 0.30196, 0.25490, 1.0);
uniform bool stair_side = false;
varying float right_wall;
varying float wall_depth;

void vertex() {
	growth_distance = dot(VERTEX, growth_axis) + 0.5;
	// Local orientation stays attached to rotating supports. Do not project
	// world-space texture coordinates through a moving module.
	right_wall = abs(NORMAL.x) > abs(NORMAL.z) ? 1.0 : 0.0;
	wall_depth = max(0.0, -VERTEX.y);
}

float stone_hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	if (growth_hidden()) discard;
	// Surface UVs already unfold the vertical wall at 1/4.5 world units.
	// The original Canvas renderer uses 70 source pixels per tile and 48
	// pixels per .65 height unit. Keep that anisotropic density, including
	// its opposite horizontal direction on the right-facing wall.
	vec2 at = UV * 4.5;
	vec2 pixels = vec2(at.x * (right_wall > 0.5 ? -1.0 : 1.0), at.y) * wall_pixels_per_unit;
	vec3 paint;
	if (right_wall > 0.5) {
		paint = texture(wall_art_right, pixels / vec2(textureSize(wall_art_right, 0))).rgb;
	} else {
		paint = texture(wall_art, pixels / vec2(textureSize(wall_art, 0))).rgb;
	}
	// Let the painted joints and stone variation supply detail. A subtle
	// depth wash recalls the original foundation shading without replacing
	// the painted wall with a uniform tint or a second procedural brick grid.
	float foundation_fade = smoothstep(0.0, 1.6, wall_depth);
	vec3 face = mix(paint, wall_wash.rgb, 0.035 * (1.0 - foundation_fade));
	ALBEDO = mix(face, wall_foot.rgb, 0.16 * foundation_fade);
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
