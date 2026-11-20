shader_type canvas_item;
uniform vec3 chapter_multiplier = vec3(1.0);
uniform vec3 chapter_offset = vec3(0.0);
uniform vec4 atlas_region = vec4(0.0,0.0,1.0,1.0);
void fragment() {
	vec4 paper = texture(TEXTURE,UV);
	vec2 local = (UV-atlas_region.xy)/atlas_region.zw;
	float feather = smoothstep(0.0,0.04,local.x) * smoothstep(0.0,0.04,1.0-local.x) * smoothstep(0.0,0.06,local.y) * smoothstep(0.0,0.06,1.0-local.y);
	COLOR = vec4(paper.rgb * chapter_multiplier + chapter_offset, paper.a * feather);
}
