# Fixture for measure_traps T17 and the warnings.sh lambda case: a lambda captures a local BY VALUE.
# Every line compiles, the harness prints ok + PASS and exits 0. The boxed counter and the TRAP lines show the truth.
extends Node

signal hit

var _ran := 0
var _failed := 0
var _fired := false


func _check(what: String, cond: bool, why := "") -> void:
	_ran += 1
	if cond:
		print("  ok    %s" % what)
	else:
		_failed += 1
		print("  FAIL  %s (%s)" % [what, why])


func _ready() -> void:
	# (b) the lambda assigns a captured local: it counts in its own copy, the outer `hits` stays 0.
	var hits := 0
	hit.connect(func(): hits += 1)
	var box := {"hits": 0}
	hit.connect(func(): box["hits"] += 1)
	hit.emit()
	_check("a miss fires no hit", hits == 0, "hits=%d" % hits)
	print("TRAP: (b) the boxed counter saw %d hit(s), the captured local %d" % [box["hits"], hits])

	# (a) the outer function reassigns after the lambda was made: the lambda keeps the old value.
	var aim := 1
	var read_aim := func() -> int: return aim
	aim = 2
	print("TRAP: (a) the lambda read aim=%d after the outer function set it to %d" % [read_aim.call(), aim])

	# What does reach the outer function: a member, and an Array written through.
	var arr: Array = [false]
	hit.connect(func(): arr[0] = true)
	var appended: Array[int] = []
	hit.connect(func(): appended.append(1))
	hit.connect(func(): _fired = true)
	hit.emit()
	print("TRAP: (boxes) member _fired=%s, arr[0]=%s, appended=%d" % [_fired, arr[0], appended.size()])

	var ok := _failed == 0
	print("DIAG-TRAP: %s %d/%d" % ["PASS" if ok else "FAIL", _ran - _failed, _ran])
	get_tree().quit(0 if ok else 1)
