extends Node

## DIAG-__NAME__: headless harness. Drives the REAL objects of the game, never a copy of their logic.
##
##   bash <godot-run skill>/godot_run.sh --path . --banner '^DIAG-__NAME__: PASS' res://__DIR__/diag___name__.tscn
##   (never a bare `godot ...` run: no isolation, no --quit-after, and its exit code proves nothing)
##
## Contract (skill godot-headless-harness):
##   - one line per check: "  ok    <name>" or "  FAIL  <name> (<why>)"
##   - the banner "DIAG-__NAME__: PASS n/n" is printed once, after EVERY check ran, and only then quit()
##   - EXPECTED is asserted, so a check that silently did not run is a FAIL, not a missing line
##   - every check that awaits is awaited
##
## Fresh from the template this harness FAILS on purpose: replace the placeholder with real checks.

## How many checks _ready runs (not counting "all checks ran"). Update it whenever you add or remove one.
const EXPECTED := 1

var _ran := 0
var _failed := 0


func _check(name: String, cond: bool, why := "") -> void:
	_ran += 1
	if cond:
		print("  ok    %s" % name)
	else:
		_failed += 1
		print("  FAIL  %s (%s)" % [name, why])


func _ready() -> void:
	# A check that awaits is a coroutine: call it with `await`, or _ready runs on to quit() before it finishes.
	await _check_placeholder()
	# Coverage asserted positively: a run where checks silently did not execute must not read as a pass.
	_check("all checks ran", _ran == EXPECTED, "ran %d of %d" % [_ran, EXPECTED])
	var ok := _failed == 0
	print("DIAG-__NAME__: %s %d/%d" % ["PASS" if ok else "FAIL", _ran - _failed, _ran])
	get_tree().quit(0 if ok else 1)


func _check_placeholder() -> void:
	# Replace with a real check, e.g.:
	#   GameState.reset()                         # autoloads are shared state: reset what you read
	#   var e := preload("res://src/enemy.tscn").instantiate()
	#   add_child(e)                              # the real scene, so _ready and @onready run
	#   var bounty: int = e.bounty                # read it now: e is freed by the time you assert
	#   e.get_node("Health").damage(9999)
	#   await get_tree().process_frame            # queue_free and signal fan-out settle on the next frame
	#   _check("kill pays the bounty", GameState.score == bounty, "score=%d bounty=%d" % [GameState.score, bounty])
	await get_tree().process_frame
	_check("placeholder replaced by real checks", false, "fresh template - write the real checks first")
