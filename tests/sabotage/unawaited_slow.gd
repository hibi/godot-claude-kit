extends Node

## A harness whose slow async check is NOT awaited and that has NO coverage count.


func _check_slow() -> void:
	await get_tree().create_timer(0.5).timeout
	print("  FAIL  the slow check finally ran its assert")


func _ready() -> void:
	print("  ok    a quick check")
	_check_slow()  # missing await
	print("DIAG: PASS")
	get_tree().quit(0)
