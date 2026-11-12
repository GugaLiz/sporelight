shader_type spatial;
render_mode unshaded, cull_disabled;

uniform sampler2D pigment : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D woodland : source_color, filter_linear_mipmap;
uniform float effect_time = 0.0;

void fragment() {
	float y = UV.y;
	vec3 paint;
	if (y < .32) paint = mix(vec3(.5804,.7373,.7137), vec3(.6588,.8078,.8157), y/.32);
	else if (y < .65) paint = mix(vec3(.6588,.8078,.8157), vec3(.5137,.7216,.7686), (y-.32)/.33);
	else paint = mix(vec3(.5137,.7216,.7686), vec3(.5176,.6902,.7255), (y-.65)/.35);
	vec2 drift = vec2(sin(UV.y*18.0+effect_time*.5),cos(UV.x*15.0-effect_time*.4))*.0015;
	paint = mix(paint, texture(pigment,UV*3.0+drift).rgb, .4);
	paint = mix(paint, texture(woodland,vec2(UV.x,1.0-UV.y)).rgb, .055);
	float band = pow(.5+.5*sin(UV.x*65.0+UV.y*31.0-effect_time*1.2),18.0);
	ALBEDO = paint + vec3(.018)*band;
	ROUGHNESS = 1.0;
}
