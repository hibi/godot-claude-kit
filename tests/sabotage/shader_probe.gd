extends SceneTree

# Shader probe for measure_traps.sh (T19), run as `--script` on a demo copy: load one shader, optionally touch it,
# and print what happened. It judges nothing; the caller counts the `SHADER ERROR` lines in the log.
#   user args: --shader=res://... --touch=none|code|rid|uniforms|material

func _initialize() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else ""
	var sh := ResourceLoader.load(args["shader"], "", ResourceLoader.CACHE_MODE_IGNORE) as Shader
	print("probe: loaded=%s" % (sh != null))
	match args.get("touch", "none"):
		"code":
			print("probe: code length %d" % sh.code.length())
		"rid":
			print("probe: rid valid=%s" % sh.get_rid().is_valid())
		"uniforms":
			print("probe: %d uniforms" % sh.get_shader_uniform_list().size())
		"material":
			var m := ShaderMaterial.new()
			m.shader = sh
			m.set_shader_parameter("strength", 0.5)
	print("probe: done")
	quit()
