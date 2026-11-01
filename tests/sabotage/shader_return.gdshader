// T19: a full-screen post effect with an early `return` in fragment(). The shader language refuses it, so the whole
// shader fails to compile and the layer draws a blank (measured: white) screen. Write the early-out as if/else.
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float strength = 0.0;

void fragment() {
	if (strength <= 0.0) {
		COLOR = texture(screen_tex, SCREEN_UV);
		return;
	}
	COLOR = texture(screen_tex, SCREEN_UV) * (1.0 - strength);
}
