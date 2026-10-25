class_name Health
extends Node

## A small component with a class_name - new class_names are only registered after `--import`.

signal died

@export var max_hp := 100

var hp := max_hp


func _ready() -> void:
	hp = max_hp


func damage(amount: int) -> void:
	if is_dead() or amount <= 0:
		return
	hp = maxi(hp - amount, 0)
	if hp == 0:
		died.emit()


func heal(amount: int) -> void:
	if is_dead() or amount <= 0:
		return
	hp = mini(hp + amount, max_hp)


func is_dead() -> bool:
	return hp <= 0
