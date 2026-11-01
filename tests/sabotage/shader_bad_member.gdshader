// T19: a spatial shader that does not compile (a vec3 has no .w).
shader_type spatial;

void fragment() {
	ALBEDO = vec3(1.0, 0.0, 0.0).w;
}
