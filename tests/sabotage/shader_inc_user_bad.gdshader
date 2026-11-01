// T19: a correct shader that includes shader_inc_bad.gdshaderinc, which does not compile.
shader_type canvas_item;
#include "shader_inc_bad.gdshaderinc"

void fragment() {
	COLOR = vec4(vec3(gck_bad(COLOR.rgb)), 1.0);
}
