# Fixture for measure_traps W1/W4: six engine warnings in one script (all of them compile).
extends Node

signal hit(amount: int)

var hp := 10


func slow() -> int:
	await get_tree().process_frame
	return 1


func _ready() -> void:
	var unused := 5
	var half := 5 / 2
	slow()
	var hp := 3
	hp + 1
	print(half, hp)
	return
	print("unreachable")
