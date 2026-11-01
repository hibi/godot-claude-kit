// T19 control: a correct sky shader. The gate must PASS it.
shader_type sky;

void sky() {
	COLOR = mix(vec3(0.2, 0.3, 0.5), vec3(0.8, 0.9, 1.0), clamp(EYEDIR.y, 0.0, 1.0));
}
