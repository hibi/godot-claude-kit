# Fixture for measure_traps W5: a node path the scene does not have. Compiles; fails only when it runs.
extends Node

@onready var hud: Node = $Hud


func _ready() -> void:
	print("TRAP: ready, hud=%s" % hud)
	get_tree().quit()
