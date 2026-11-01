// T19 control: a correct shader include.
float gck_luma(vec3 c) {
	return dot(c, vec3(0.299, 0.587, 0.114));
}
