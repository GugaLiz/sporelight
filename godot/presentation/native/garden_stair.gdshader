shader_type spatial;
render_mode cull_disabled;
#include "res://presentation/native/garden_growth.gdshaderinc"

uniform sampler2D original_stair : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D original_stone : source_color, filter_linear_mipmap, repeat_disable;
uniform bool riser = false;
uniform bool connector = false;
uniform float face_repeat = 1.0;
varying vec3 stone_position;

void vertex() {
	growth_distance = dot(VERTEX, growth_axis) + 0.5;
	stone_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float stone_hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	if (growth_hidden()) discard;
	// UVs already rectify the authored stair painting onto each physical face.
	vec3 paint = texture(original_stair, UV).rgb;
	float value = dot(paint, vec3(0.2126, 0.7152, 0.0722));
	vec3 stone = mix(vec3(value), paint, 0.65) * vec3(1.12, 1.06, 0.91);
	// The source riser is painted in shadow. Lift that baked shadow before
	// scene lighting, so it does not turn every step into a dark stripe.
	if (riser) stone = mix(stone, vec3(0.60, 0.56, 0.44), 0.42);
	// UV2 describes each real face, independently of the painted atlas UVs.
	// Split the stone across the flight, never diagonally across its noses.
	vec2 face = clamp(UV2, vec2(0.0), vec2(1.0));
	float block = face.x * 2.0 * face_repeat;
	vec2 grain_uv = vec2(0.27, 0.35) + vec2(fract(block), face.y) * vec2(0.32, 0.34);
	vec3 grain = texture(original_stone, grain_uv).rgb;
	// Painted stair silhouettes contain a second isometric perspective. Keep
	// only a trace of their color; the real geometry supplies all face depth.
	stone = mix(stone, grain * (riser ? 0.76 : 0.96), 0.94);
	float edge = min(fract(block), 1.0 - fract(block));
	float aa = max(fwidth(block), 0.003);
	float joint = 1.0 - smoothstep(0.008, 0.008 + aa, edge);
	stone *= 1.0 - joint * 0.24;
	if (riser) {
		// Thin shadow below the lip and soft darkening where the riser meets
		// the next tread keep depth readable without broad black stripes.
		float lip_shadow = 1.0 - smoothstep(0.0, 0.16, face.y);
		float foot_shadow = smoothstep(0.80, 1.0, face.y);
		stone *= 1.0 - lip_shadow * 0.19 - foot_shadow * 0.10;
	} else {
		float nose = 1.0 - smoothstep(0.035, 0.18, face.y);
		float back_joint = smoothstep(0.83, 1.0, face.y);
		stone = mix(stone, vec3(0.83, 0.77, 0.60), nose * 0.28);
		stone *= 1.0 - back_joint * 0.26;
	}
	if (connector) {
		// Use the original paving's interior grain, without any baked stair
		// silhouette. Stable tread/block seeds vary the crop and mortar layout.
		float course = floor(stone_position.y / (0.65 / 6.0) + 0.002) + (riser ? 1.0 : 0.0);
		float split = 0.30 + stone_hash(vec2(course, 7.0)) * 0.40;
		float right_block = step(split, face.x);
		float seed = stone_hash(vec2(course, right_block + 13.0));
		float across = right_block > 0.5 ? (face.x - split) / (1.0 - split) : face.x / split;
		vec2 grain_at = vec2(mix(across, 1.0 - across, step(0.5, seed)), face.y);
		vec2 crop = vec2(0.29, 0.39) + vec2(seed, stone_hash(vec2(course, 31.0))) * 0.025;
		vec3 dressed = texture(original_stone, crop + grain_at * vec2(0.24, 0.23)).rgb;
		dressed *= (riser ? 0.76 : 0.88) * (0.93 + seed * 0.14);
		float joint_aa = max(fwidth(face.x), 0.002);
		// Most treads are a single long slab. An occasional offset joint is
		// enough variation at this scale; a split on every step looks tiled.
		float seam = (1.0 - smoothstep(0.002, 0.002 + joint_aa, abs(face.x - split))) * step(0.64, stone_hash(vec2(course, 47.0)));
		dressed *= 1.0 - seam * 0.16;
		if (riser) {
			dressed *= 1.0 - (1.0 - smoothstep(0.0, 0.12, face.y)) * 0.12;
		} else {
			// A narrow worn lip, rather than another bold line across each step.
			float lip = 1.0 - smoothstep(0.0, 0.10, face.y);
			dressed = mix(dressed, dressed * 1.16, lip);
			dressed *= mix(0.92, 1.0, smoothstep(0.0, 0.035, min(face.x, 1.0 - face.x)));
			dressed *= 1.0 - smoothstep(0.88, 1.0, face.y) * 0.18;
		}
		stone = dressed;
	}
	ALBEDO = stone;
	ROUGHNESS = 1.0;
	EMISSION = growth_light();
}
