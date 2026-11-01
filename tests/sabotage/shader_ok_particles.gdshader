// T19 control: a correct particles shader. The gate must PASS it.
shader_type particles;

void start() {
	TRANSFORM[3].xyz = vec3(0.0);
	VELOCITY = vec3(0.0, 1.0, 0.0);
}

void process() {
	VELOCITY.y -= 9.8 * DELTA;
}
