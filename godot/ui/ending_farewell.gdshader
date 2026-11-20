shader_type canvas_item;
// Split the original free arm at the sleeve for rigid shoulder rotation.
// Both sprites sample the same painting: no stretching the palm or face.
uniform bool arm_only = false;
uniform float head_angle = 0.0;
varying vec4 tint;
void vertex() { tint = COLOR; }
void fragment() {
	vec2 uv = UV;
	float sleeve = smoothstep(0.597,0.601,uv.x)*smoothstep(0.583,0.587,uv.y);
	float hand = smoothstep(0.663,0.667,uv.x)*smoothstep(0.493,0.497,uv.y);
	float arm = max(sleeve,hand)*(1.0-smoothstep(0.646,0.650,uv.y));
	vec2 neck = vec2(0.491, 0.573);
	float head = (1.0-smoothstep(0.550,0.580,UV.y)) * (1.0-smoothstep(0.650,0.680,UV.x));
	float a = arm_only ? 0.0 : head_angle * head;
	vec2 d = uv-neck;
	uv = neck+vec2(cos(a)*d.x+sin(a)*d.y,-sin(a)*d.x+cos(a)*d.y);
	COLOR = texture(TEXTURE,uv)*tint;
	COLOR.a *= arm_only ? arm : 1.0-arm;
}
