shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never;
uniform vec4 tint : source_color = vec4(0.98, 0.91, 0.72, 1.0);
uniform float flap = 1.0;
float ellipse(vec2 p, vec2 c, vec2 r) { return length((p-c)/r); }
float stroke(vec2 p, vec2 a, vec2 b, float width) {
	vec2 d=b-a;
	return 1.0-smoothstep(width,width+0.015,length(p-a-d*clamp(dot(p-a,d)/dot(d,d),0.0,1.0)));
}
void fragment() {
	vec2 p=UV*2.0-1.0;
	vec2 w=vec2(abs(p.x)/max(flap,0.32),p.y);
	// Broad scalloped forewings and rounded hindwings, hinged at the thorax.
	float upper=ellipse(w,vec2(0.43,-0.30),vec2(0.46,0.55));
	float lower=ellipse(w,vec2(0.32,0.40),vec2(0.33,0.34));
	float shape=min(upper,lower);
	float aa=max(fwidth(shape),0.012);
	float wing=1.0-smoothstep(1.0-aa,1.0+aa,shape);
	float rim=smoothstep(0.82,0.99,shape);
	vec3 paint=mix(tint.rgb,vec3(0.70,0.79,0.58),smoothstep(-0.35,0.8,w.y)*0.44);
	paint=mix(paint,vec3(0.61,0.55,0.34),rim*0.65);
	float vein=max(stroke(w,vec2(0.035,0.05),vec2(0.70,-0.60),0.009),stroke(w,vec2(0.035,0.05),vec2(0.65,-0.05),0.008));
	vein=max(vein,stroke(w,vec2(0.035,0.06),vec2(0.49,0.56),0.008));
	paint=mix(paint,vec3(0.72,0.64,0.39),vein*0.38);
	float spot=1.0-smoothstep(0.70,1.0,ellipse(w,vec2(0.63,-0.42),vec2(0.09,0.12)));
	paint=mix(paint,vec3(1.0,0.98,0.86),spot*0.9);
	float body=1.0-smoothstep(0.86,1.0,ellipse(p,vec2(0.0,0.08),vec2(0.055,0.48)));
	float head=1.0-smoothstep(0.85,1.0,ellipse(p,vec2(0.0,-0.36),vec2(0.079,0.09)));
	float antenna=stroke(vec2(abs(p.x),p.y),vec2(0.025,-0.39),vec2(0.16,-0.68),0.012);
	float ink=max(max(body,head),antenna);
	ALBEDO=mix(paint,vec3(0.37,0.39,0.23),ink);
	ALPHA=max(wing,ink)*tint.a;
}
