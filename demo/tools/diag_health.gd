extends Node

## Example headless harness: drives the REAL Health component and the REAL enemy scene, never a copy of their logic.
##
##   bash <godot-run skill>/godot_run.sh --path . --banner '^DIAG-HEALTH: PASS' res://tools/diag_health.tscn
##
## Contract every harness here follows:
##   - one line per check: "  ok    <name>" or "  FAIL  <name> (<why>)"
##   - a final banner "DIAG-HEALTH: PASS n/n" printed only after EVERY check really ran
##   - exit code 1 on any failure - but the runner still greps for SCRIPT ERROR and the banner,
##     because a script that fails to parse leaves a bare node behind that prints nothing and exits 0.

const ENEMY := preload("res://src/enemy.tscn")

var _ran := 0
var _failed := 0


func _check(what: String, cond: bool, why := "") -> void:
	_ran += 1
	if cond:
		print("  ok    %s" % what)
	else:
		_failed += 1
		print("  FAIL  %s (%s)" % [what, why])


func _ready() -> void:
	# Every check that awaits is a coroutine: it MUST be awaited, or _ready runs on to quit() before it finishes.
	_check_damage_clamps()
	_check_heal_does_not_revive()
	await _check_kill_pays_bounty()
	# Coverage asserted positively: a run where checks silently did not execute must not read as a pass.
	const EXPECTED := 3
	_check("all checks ran", _ran == EXPECTED, "ran %d of %d" % [_ran, EXPECTED])
	var ok := _failed == 0
	print("DIAG-HEALTH: %s %d/%d" % ["PASS" if ok else "FAIL", _ran - _failed, _ran])
	get_tree().quit(0 if ok else 1)


func _check_damage_clamps() -> void:
	var h := Health.new()
	h.max_hp = 50
	add_child(h)
	h.damage(80)
	# Assert the VALUE, not just "something happened".
	_check("damage clamps at 0", h.hp == 0 and h.is_dead(), "hp=%d" % h.hp)
	h.queue_free()


func _check_heal_does_not_revive() -> void:
	var h := Health.new()
	add_child(h)
	h.damage(h.max_hp)
	h.heal(25)
	_check("heal does not revive a corpse", h.hp == 0, "hp=%d" % h.hp)
	h.queue_free()


func _check_kill_pays_bounty() -> void:
	GameState.reset()  # autoloads are shared state: reset what you read
	var e := ENEMY.instantiate()
	add_child(e)
	var bounty: int = e.bounty
	e.get_node("Health").damage(9999)
	# queue_free and signal fan-out settle on the next frame.
	await get_tree().process_frame
	_check("kill pays the bounty once", GameState.score == bounty and not is_instance_valid(e),
		"score=%d bounty=%d alive=%s" % [GameState.score, bounty, is_instance_valid(e)])
