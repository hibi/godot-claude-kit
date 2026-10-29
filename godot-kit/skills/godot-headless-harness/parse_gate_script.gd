extends SceneTree

## PARSE GATE without a file in the project: does every script under res:// compile?
## The same walk and checks as templates/parse_gate.gd, run as `--script` from this skill's directory - use gate.sh,
## which picks this when the project has no gate scene of its own and passes the path the engine understands. godot-ci's
## ci.sh does the same, and `ci.sh install` vendors a copy into res://tools/ci/ (the walk skips this file itself).
##
##   bash gate.sh --path <project>          (never a bare `godot ...` run: no isolation, no backstop)
##
## User args (after `++`): --min=N (fewer scripts fails; default 1, or PARSE_GATE_MIN), --skip=res://dir (repeatable,
## added to res://addons), --include=res://dir (repeatable: check this directory although it lies under a skipped one,
## e.g. the add-on you are writing in res://addons/<name>; the other skipped directories stay skipped). Measured on Godot 4.7.2: the project's autoloads are registered by the time this runs, so a
## correct script naming an autoload compiles here - unlike `--check-only --script <file>`, which reports a false
## "Identifier not found". A syntax error and `Vector2.ZERO.z` both come back as FAIL.

var _skip: Array[String] = ["res://addons"]
var _include: Array[String] = []
var _broken: Array[String] = []
var _bad_args: Array[String] = []
var _count := 0


func _walk(dir: String) -> void:
	if dir in _skip:
		# A skipped directory is not walked, except the --include directories below it.
		for inc in _include:
			if inc.begins_with(dir + "/"):
				_walk(inc)
		return
	if FileAccess.file_exists(dir.path_join(".gdignore")):
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
	# Fresh load (CACHE_MODE_IGNORE): a cached copy would be handed back without a re-parse. Never this script itself:
	# re-loading the RUNNING gate this way crashed the engine (signal 11) when a copy was vendored into res://tools/ci/.
	if path == get_script().resource_path:
		return
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
	var env_min := OS.get_environment("PARSE_GATE_MIN")
	if env_min.is_valid_int():
		min_count = env_min.to_int()
	elif not env_min.is_empty():
		_bad_args.append("PARSE_GATE_MIN=%s" % env_min)
	# An argument this gate does not know FAILS it: ignored, a typo like `--mn=40` would leave the floor at 1 and pass.
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--min=") and a.trim_prefix("--min=").is_valid_int():
			min_count = a.trim_prefix("--min=").to_int()
		elif a.begins_with("--skip=res://"):
			_skip.append(a.trim_prefix("--skip=").trim_suffix("/"))
		elif a.begins_with("--include=res://") and DirAccess.dir_exists_absolute(a.trim_prefix("--include=")):
			_include.append(a.trim_prefix("--include=").trim_suffix("/"))
		else:
			_bad_args.append(a)
	_walk("res://")
	for b in _broken:
		print("  FAIL  %s" % b)
	for a in _bad_args:
		print("  FAIL  unknown or malformed argument '%s' (known: --min=N, --skip=res://dir, --include=res://dir, PARSE_GATE_MIN=N)" % a)
	var ok := _broken.is_empty() and _bad_args.is_empty() and _count >= min_count and _count > 0
	if _count < min_count or _count == 0:
		print("  FAIL  only %d scripts found under res://, expected at least %d" % [_count, min_count])
	print("PARSE-GATE: %s - %d scripts, %d broken" % ["PASS" if ok else "FAIL", _count, _broken.size()])
	quit(0 if ok else 1)
