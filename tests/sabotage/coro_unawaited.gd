# Fixture for measure_traps W3: coroutines called without await (both lines compile).
extends Node


func slow_void() -> void:
	await get_tree().process_frame


func slow_int() -> int:
	await get_tree().process_frame
	return 1


func _ready() -> void:
	slow_void()
	slow_int()
