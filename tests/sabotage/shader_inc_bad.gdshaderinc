// T19: a shader include that does not compile (a vec3 has no .w).
float gck_bad(vec3 c) {
	return c.w;
}
