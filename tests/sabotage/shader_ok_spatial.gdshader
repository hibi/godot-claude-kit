// T19 control: a correct spatial shader with render modes and a hinted uniform. The gate must PASS it.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;

uniform vec4 tint : source_color = vec4(1.0, 0.5, 0.2, 1.0);

void vertex() {
	VERTEX.y += sin(TIME) * 0.1;
}

void fragment() {
	ALBEDO = tint.rgb;
}
