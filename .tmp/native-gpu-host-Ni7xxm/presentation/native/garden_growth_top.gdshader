shader_type spatial;
render_mode cull_disabled;
#include "res://presentation/native/garden_growth.gdshaderinc"

uniform sampler2D original_paving : source_color, filter_linear_mipmap, repeat_disable;
uniform vec4 tint : source_color = vec4(1.0);

void vertex() { growth_distance = dot(VERTEX, growth_axis) + 0.5; }
void fragment() {
	if (growth_hidden()) discard;
	ALBEDO = texture(original_paving, UV).rgb * tint.rgb;
	ROUGHNESS = 1.0;
	EMISSION = growth_light();
}
