# Fixture for measure_traps T18: a CORRECT editor plugin script, to show that the parse gate (a plain scene run, not
# the editor) compiles editor-only classes fine once res://addons/<name> is taken out of its SKIP list.
@tool
extends EditorPlugin


func _enter_tree() -> void:
	print("addon_probe: init")
	add_tool_menu_item("Addon probe", func(): print(get_editor_interface().get_editor_paths().get_config_dir()))


func _exit_tree() -> void:
	remove_tool_menu_item("Addon probe")
