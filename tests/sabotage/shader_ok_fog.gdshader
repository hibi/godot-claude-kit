// T19 control: a correct fog shader. The gate must PASS it.
shader_type fog;

void fog() {
	DENSITY = 0.5;
	ALBEDO = vec3(0.8);
}
