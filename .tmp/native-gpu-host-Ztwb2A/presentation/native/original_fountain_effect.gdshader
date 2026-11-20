shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never;
uniform int kind = 0; // 0 continuous jet segment, 1 basin arc, 2 falling drop
uniform vec2 source_radius = vec2(1.0);
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	if (kind == 0) {
		float outer = 1.0 - smoothstep(.65, 1.0, abs(p.x));
		float inner = 1.0 - smoothstep(.17, .44, abs(p.x));
		ALBEDO = mix(vec3(.65,.84,.84),vec3(.94,1.0,.95),inner);
		ALPHA = outer * mix(.49,.87,inner);
	} else if (kind == 1) {
		float width = .65 / max(source_radius.x, source_radius.y);
		float arc = 1.0 - smoothstep(width*.4,width*1.6,abs(length(p)-.98));
		vec2 point = vec2(-2.0,-5.0) + p*source_radius;
		// Original arcs are painted before the pedestal; preserve that occlusion.
		float pedestal = step(length((point-vec2(0.0,-12.0))/vec2(12.0,6.0)),1.0);
		float gap = step(atan(p.y,p.x),-.3*3.14159265);
		ALBEDO = vec3(.94,.95,.86);
		ALPHA = arc * .43 * (1.0-pedestal) * (1.0-gap);
	} else {
		ALBEDO = vec3(.86,.92,.84);
		ALPHA = (1.0-smoothstep(.7,1.0,length(p))) * .71;
	}
}
