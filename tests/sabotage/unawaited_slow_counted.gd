extends Node

## The same un-awaited slow check as unawaited_slow.gd, but the harness asserts its coverage count.

const EXPECTED := 2

var _ran := 0


func _check(name: String, cond: bool) -> void:
	_ran += 1
	print(("  ok    %s" if cond else "  FAIL  %s") % name)


func _check_slow() -> void:
	await get_tree().create_timer(0.5).timeout
	_check("the slow check", false)


func _ready() -> void:
	_check("a quick check", true)
	_check_slow()  # missing await
	var ok := _ran == EXPECTED
	if not ok:
		print("  FAIL  all checks ran (ran %d of %d)" % [_ran, EXPECTED])
	print("DIAG: %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)
