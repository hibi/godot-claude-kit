// T19 control: includes shader_inc_ok.gdshaderinc by a RELATIVE path. The gate must PASS it.
shader_type canvas_item;
#include "shader_inc_ok.gdshaderinc"

void fragment() {
	COLOR = vec4(vec3(gck_luma(COLOR.rgb)), 1.0);
}
