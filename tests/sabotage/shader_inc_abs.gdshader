// T19 control: includes shader_inc_ok.gdshaderinc by its res:// path (measure_traps puts it in res://fx/).
shader_type canvas_item;
#include "res://fx/shader_inc_ok.gdshaderinc"

void fragment() {
	COLOR = vec4(vec3(gck_luma(COLOR.rgb)), 1.0);
}
