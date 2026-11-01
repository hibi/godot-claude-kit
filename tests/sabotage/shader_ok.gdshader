// T19 control: shader_return.gdshader with the early-out written as if/else. Compiles.
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float strength = 0.0;

void fragment() {
	if (strength <= 0.0) {
		COLOR = texture(screen_tex, SCREEN_UV);
	} else {
		COLOR = texture(screen_tex, SCREEN_UV) * (1.0 - strength);
	}
}
