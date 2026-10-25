extends Node3D

## The demo "game": spawns a few enemies and shows the score as they die.

const ENEMY := preload("res://src/enemy.tscn")

@export var enemy_count := 3

@onready var score_label: Label = $HUD/Score


func _ready() -> void:
	GameState.score_changed.connect(_on_score_changed)
	for i in enemy_count:
		var e := ENEMY.instantiate()
		e.position = Vector3(i * 2.0, 0.0, 0.0)
		add_child(e)


func _on_score_changed(s: int) -> void:
	score_label.text = "score: %d" % s
	print("score: %d" % s)
