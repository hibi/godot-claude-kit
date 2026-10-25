class_name Health
extends Node

## Sabotaged copy of demo/src/health.gd: damage() no longer clamps at 0. Replaces the real file for one run.

signal died

@export var max_hp := 100

var hp := max_hp


func _ready() -> void:
	hp = max_hp


func damage(amount: int) -> void:
	if is_dead() or amount <= 0:
		return
	hp = hp - amount
	if hp <= 0:
		died.emit()


func heal(amount: int) -> void:
	if is_dead() or amount <= 0:
		return
	hp = mini(hp + amount, max_hp)


func is_dead() -> bool:
	return hp <= 0
