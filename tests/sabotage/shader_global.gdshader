// T19 control: reads a global uniform that project.godot declares under [shader_globals] (measure_traps adds it).
shader_type canvas_item;

global uniform vec4 gck_tint;

void fragment() {
	COLOR = gck_tint;
}
