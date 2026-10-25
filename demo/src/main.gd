extends Node3D

## The demo "game": spawns a few enemies and prints the score as they die.

const ENEMY := preload("res://src/enemy.tscn")

@export var enemy_count := 3


func _ready() -> void:
	GameState.score_changed.connect(func(s: int) -> void: print("score: %d" % s))
	for i in enemy_count:
		var e := ENEMY.instantiate()
		e.position = Vector3(i * 2.0, 0.0, 0.0)
		add_child(e)
