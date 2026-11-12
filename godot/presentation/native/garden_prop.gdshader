shader_type spatial;
render_mode unshaded, cull_disabled, depth_prepass_alpha;

// Reuse the authored bitmap; grade its painted materials for the garden.
uniform sampler2D original_paint : source_color, filter_linear_mipmap, repeat_disable;
uniform int prop_kind = 0; // 0 flowerbed, 1 root, 2 collectible
// Original defaults preserve the approved first and second garden exactly.
// Later chapters set their own stone palette on a separate cached material.
uniform vec3 stone_tint = vec3(1.12, 1.04, 0.77);
uniform vec3 plant_tint = vec3(0.86, 0.84, 0.73);
uniform float stone_saturation = 0.26;

void fragment() {
	vec4 paint = texture(original_paint, UV);
	float value = dot(paint.rgb, vec3(0.2126, 0.7152, 0.0722));
	vec3 color = paint.rgb;
	if (prop_kind == 0) {
		float stone = smoothstep(0.49, 0.69, UV.y);
		vec3 limestone = mix(vec3(value), color, stone_saturation) * stone_tint;
		color = mix(color, limestone, stone * 0.90);
		color = mix(vec3(value), color, 0.86) * plant_tint;
	} else if (prop_kind == 1) {
		color = mix(vec3(value), color, 0.72) * vec3(0.83, 0.85, 0.71);
		float bright = smoothstep(0.44, 0.78, min(paint.r, min(paint.g, paint.b)));
		paint.a *= 1.0 - bright * (1.0 - smoothstep(0.24, 0.60, UV.y)) * 0.94;
	} else {
		// Keep the original seed inside its orb; suppress the UI rim/satellites.
		float radius = length((UV - vec2(0.49, 0.55)) * vec2(1.30, 1.0));
		paint.a *= 1.0 - smoothstep(0.29, 0.35, radius);
		color = mix(vec3(value), color, 0.76) * vec3(0.94, 0.88, 0.65);
	}
	ALBEDO = color * COLOR.rgb;
	ALPHA = paint.a * COLOR.a;
}
