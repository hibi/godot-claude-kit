extends Node

## PARSE GATE: does every script under ROOTS compile?
##
##   bash <godot-run skill>/godot_run.sh --path . --banner '^PARSE-GATE: PASS' res://tools/ci/parse_gate.tscn
##   (never a bare `godot …` run: no isolation, no --quit-after, and its exit code proves nothing)
##
## Why a scene and not a flag: `--import` (and `--export-release`) do not parse-check scripts - a hard syntax error
## passes both with exit 0; `--check-only --script <file>` does report it, but also reports a false
## "Identifier not found: <Autoload>" on every script that names an autoload; Scripts loaded by a running project
## (this scene, or the skill's parse_gate_script.gd run by gate.sh) do see the autoloads - measured - so they
## load honestly
##
## Each script is loaded fresh (CACHE_MODE_IGNORE, or a cached copy would be handed back without a re-parse) and must
## come back as a script that can instantiate, or one declared @abstract; A floor on the count keeps a walk that found
## nothing from reading as a pass; The runner should still grep the log for `SCRIPT ERROR` / `Parse Error`
##
## Every .gdshader is compiled too: `--import` and the script checks never compile a shader, and a shader that does not
## compile draws a blank (measured: white) layer in the game; Loading alone compiles nothing; get_rid() does, also
## headless; On Godot 4.5+ a Logger names the file and line; on 4.4 (no Logger) only the log's `SHADER ERROR` /
## `ERROR:` lines tell, right after the `shader <path>` line - the runner fails on them

## Directories to scan; Hidden directories and directories holding a `.gdignore` are always skipped
const ROOTS := ["res://"]
## Directories under ROOTS to leave out: third-party addons, fixtures that are broken ON PURPOSE
const SKIP := ["res://addons"]
## Fewer scripts than this fails the gate; Set it a little under today's count; override with PARSE_GATE_MIN
const MIN_SCRIPTS := 1

var _broken: Array[String] = []
var _count := 0
var _shaders := 0
var _shader_errors: Array = []  # [line, message], appended by the Logger while a shader compiles
var _logger: Object = null


func _walk(dir: String) -> void:
	if dir in SKIP or FileAccess.file_exists(dir.path_join(".gdignore")):
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
		elif entry.ends_with(".gdshader"):
			_check_shader(path)
		entry = d.get_next()
	d.list_dir_end()


func _check(path: String) -> void:
	# Re-loading the gate's own running script with CACHE_MODE_IGNORE crashes the engine (signal 11, measured on 4.7.2)
	if path == get_script().resource_path:
		return
	_count += 1
	var s := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as Script
	if s == null:
		_broken.append("%s (did not load)" % path)
	elif not s.can_instantiate() and not _is_abstract(s):
		_broken.append("%s (does not compile)" % path)


func _is_abstract(s: Script) -> bool:
	# Script.is_abstract() only exists on engines with @abstract support
	return s.has_method("is_abstract") and s.call("is_abstract")


func _check_shader(path: String) -> void:
	_shaders += 1
	var sh := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as Shader
	if sh == null:
		_broken.append("%s (did not load)" % path)
		return
	if _logger == null:
		print("  shader  %s" % path)
	var before := _shader_errors.size()
	var _rid := sh.get_rid()  # compiles it (lazily: a plain load compiles nothing)
	if _shader_errors.size() > before:
		var e: Array = _shader_errors[before]
		_broken.append("%s:%d (shader does not compile: %s)" % [path, e[0], e[1]])


func _start_shader_logger() -> void:
	# Logger and OS.add_logger exist from Godot 4.5 on; Built from source at run time, so this file still compiles on 4.4
	if not ClassDB.class_exists("Logger"):
		return
	var gs := GDScript.new()
	gs.source_code = "extends Logger\nvar sink: Array\n" \
		+ "func _log_error(_fn, _file, line, code, _why, _notify, error_type, _bt):\n" \
		+ "\tif error_type == ERROR_TYPE_SHADER:\n\t\tsink.append([line, code])\n"
	if gs.reload() != OK:
		return
	_logger = gs.new()
	_logger.set("sink", _shader_errors)
	OS.call("add_logger", _logger)


func _ready() -> void:
	var min_count := MIN_SCRIPTS
	var env_min := OS.get_environment("PARSE_GATE_MIN")
	if env_min.is_valid_int():
		min_count = env_min.to_int()
	elif not env_min.is_empty():
		# Not a number: to_int() would make it 0 and drop the floor without a word
		_broken.append("PARSE_GATE_MIN=%s (not a whole number)" % env_min)
	_start_shader_logger()
	for r in ROOTS:
		_walk(r)
	if _logger != null:
		OS.call("remove_logger", _logger)
	for b in _broken:
		print("  FAIL  %s" % b)
	var ok := _broken.is_empty() and _count >= min_count and _count > 0
	if _count < min_count or _count == 0:
		print("  FAIL  only %d scripts found under %s, expected at least %d" % [_count, ROOTS, min_count])
	print("PARSE-GATE: %s - %d scripts, %d shaders, %d broken" % ["PASS" if ok else "FAIL", _count, _shaders, _broken.size()])
	get_tree().quit(0 if ok else 1)
