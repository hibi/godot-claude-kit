extends Node3D

## Uses both the autoload and the class_name: a kill pays out score.

@export var bounty := 10

@onready var health: Health = $Health


func _ready() -> void:
	health.died.connect(_on_died)


func _on_died() -> void:
	GameState.add_score(bounty)
	queue_free()
