shader_type canvas_item;
uniform vec2 extent = vec2(200.0, 140.0);
varying vec2 local_uv;
void vertex() {
	local_uv = VERTEX / extent;
}
void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float radius = min(22.0, extent.y * 0.2);
	vec2 p = local_uv * extent;
	vec2 q = abs(p - extent * 0.5) - (extent * 0.5 - vec2(radius));
	float rounded = 1.0 - smoothstep(-1.0, 1.0, length(max(q, vec2(0.0))) + min(max(q.x,q.y),0.0) - radius);
	c.a *= rounded * (1.0-smoothstep(0.52,1.0,local_uv.y));
	COLOR = c;
}
