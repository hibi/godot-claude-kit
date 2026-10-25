extends SceneTree

## PARSE GATE without a file in the project: does every script under res:// compile?
## The same walk and checks as templates/parse_gate.gd, run as `--script` from this skill's directory - use gate.sh,
## which picks this when the project has no gate scene of its own and passes the path the engine understands.
##
##   bash gate.sh --path <project>          (never a bare `godot ...` run: no isolation, no backstop)
##
## User args (after `++`): --min=N (fewer scripts fails; default 1, or PARSE_GATE_MIN), --skip=res://dir (repeatable,
## added to res://addons). Measured on Godot 4.7.2: the project's autoloads are registered by the time this runs, so a
## correct script naming an autoload compiles here - unlike `--check-only --script <file>`, which reports a false
## "Identifier not found". A syntax error and `Vector2.ZERO.z` both come back as FAIL.

var _skip: Array[String] = ["res://addons"]
var _broken: Array[String] = []
var _count := 0


func _walk(dir: String) -> void:
	if dir in _skip or FileAccess.file_exists(dir.path_join(".gdignore")):
		return
	var d := DirAccess.open(dir)
	if d == null:
		_broken.append("%s (cannot open directory)" % dir)
		return
	d.list_dir_begin()
	var entry := d.get_next()
	while entry != "":
		var path := dir.path_join(entry)
		if d.current_is_dir():
			if not entry.begins_with("."):
				_walk(path)
		elif entry.ends_with(".gd"):
			_check(path)
		entry = d.get_next()
	d.list_dir_end()


func _check(path: String) -> void:
	# Fresh load (CACHE_MODE_IGNORE): a cached copy would be handed back without a re-parse. This script lives outside
	# res://, so the walk never reaches it (re-loading a RUNNING gate script this way crashed the engine).
	_count += 1
	var s := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as Script
	if s == null:
		_broken.append("%s (did not load)" % path)
	elif not s.can_instantiate() and not _is_abstract(s):
		_broken.append("%s (does not compile)" % path)


func _is_abstract(s: Script) -> bool:
	# Script.is_abstract() only exists on engines with @abstract support.
	return s.has_method("is_abstract") and s.call("is_abstract")


func _initialize() -> void:
	var min_count := 1
	if OS.has_environment("PARSE_GATE_MIN"):
		min_count = OS.get_environment("PARSE_GATE_MIN").to_int()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--min="):
			min_count = a.trim_prefix("--min=").to_int()
		elif a.begins_with("--skip="):
			_skip.append(a.trim_prefix("--skip=").trim_suffix("/"))
	_walk("res://")
	for b in _broken:
		print("  FAIL  %s" % b)
	var ok := _broken.is_empty() and _count >= min_count and _count > 0
	if _count < min_count or _count == 0:
		print("  FAIL  only %d scripts found under res://, expected at least %d" % [_count, min_count])
	print("PARSE-GATE: %s - %d scripts, %d broken" % ["PASS" if ok else "FAIL", _count, _broken.size()])
	quit(0 if ok else 1)
