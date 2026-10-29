# Fixture for measure_traps T18: the script of an ENABLED editor plugin that does not compile (a stand-in for an
# add-on calling an API the engine does not have). The editor run and the kit's gate both exit 0 on it.
@tool
extends EditorPlugin


func _enter_tree() -> void:
	print("addon_probe: init")
	var x = = 5
