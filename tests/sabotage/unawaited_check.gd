extends Node

## A harness whose async check is NOT awaited.


func _check_async() -> void:
	await get_tree().process_frame
	print("  FAIL  the async check finally ran its assert")


func _ready() -> void:
	_check_async()  # missing await
	print("DIAG: PASS")
	get_tree().quit(0)
