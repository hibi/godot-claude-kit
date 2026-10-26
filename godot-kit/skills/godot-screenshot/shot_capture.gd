extends SceneTree

## Screenshot capture for shot.sh. Runs as `--script` from OUTSIDE the project: no file of it lands in res://.
## Autoloads are present (measured), so a scene that uses them runs as in the game.
##
## User args (after `++`): --scene=res://x.tscn --out=<abs.png> --size=WxH [--settle=N]
##                         [--golden=<abs.png> [--max-rmse=F] | --update-golden]
## Prints FAIL lines for everything that is wrong and `SHOT: PASS` only when every check passed. The runner judges
## the log; the exit code alone means nothing (a headless run of this exits 0 without ever drawing a pixel).

var _failed := false


func _initialize() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else ""
	var scene_path: String = args.get("scene", "")
	var out: String = args.get("out", "")
	var size_s: String = args.get("size", "")
	var settle := int(args.get("settle", "10"))
	var golden: String = args.get("golden", "")
	var max_rmse := float(args.get("max-rmse", "0.5"))

	if DisplayServer.get_name() == "headless":
		# --headless renders nothing: frame_post_draw never fires and the viewport texture is null. Say so now
		# instead of waiting for --quit-after.
		_finish("FAIL needs a display: this run is --headless, which never draws a frame")
		return
	if scene_path.is_empty() or out.is_empty() or not "x" in size_s:
		_finish("FAIL usage: --scene=res://... --out=<png> --size=WxH")
		return
	var want := Vector2i(int(size_s.get_slice("x", 0)), int(size_s.get_slice("x", 1)))
	var packed := load(scene_path) as PackedScene
	if packed == null:
		_finish("FAIL cannot load scene %s" % scene_path)
		return
	change_scene_to_packed(packed)

	for i in settle:
		await process_frame
	# The frame must be DRAWN before it is read: grabbed earlier (e.g. in _ready) the viewport is uniform black.
	await RenderingServer.frame_post_draw

	# Who rendered the frame. A golden is compared only when ALL of this matches: the same driver on the same GPU
	# renders byte-identical frames, Vulkan vs OpenGL (or another GPU / driver version) does not.
	var who := {"driver": RenderingServer.get_current_rendering_driver_name(),
			"adapter": RenderingServer.get_video_adapter_name(),
			"api": RenderingServer.get_video_adapter_api_version(),
			"engine": Engine.get_version_info()["string"]}
	print("shot: scene=%s driver=%s adapter=%s api=%s" % [scene_path, who.driver, who.adapter, who.api])
	var tex := root.get_texture()
	var img := tex.get_image() if tex else null
	if img == null or img.is_empty():
		_finish("FAIL viewport image is null")
		return
	img.convert(Image.FORMAT_RGBA8)
	var err := img.save_png(out)
	if err != OK:
		_fail("FAIL cannot write %s (error %d)" % [out, err])
	else:
		print("shot: wrote %s (%dx%d)" % [out, img.get_width(), img.get_height()])
	if img.get_size() != want:
		_fail("FAIL image is %dx%d, expected %dx%d (display scaling or a project window override?)"
				% [img.get_width(), img.get_height(), want.x, want.y])
	var c0 := img.get_pixel(0, 0)
	var flat := Image.create(img.get_width(), img.get_height(), false, Image.FORMAT_RGBA8)
	flat.fill(c0)
	if float(img.compute_image_metrics(flat, false)["max"]) == 0.0:
		# A 3D scene without a current camera, or a capture before the first draw: a valid PNG of one color.
		_fail("FAIL blank frame: every pixel is %s (no camera? nothing visible? captured too early?)" % c0)

	if args.has("update-golden") and not golden.is_empty() and not _failed:
		_write_golden(img, golden, scene_path, want, who)
	elif not golden.is_empty():
		_compare(img, golden, scene_path, want, who, max_rmse)

	_finish("SHOT: PASS %s" % out if not _failed else "")


func _compare(img: Image, golden: String, scene_path: String, want: Vector2i, who: Dictionary,
		max_rmse: float) -> void:
	var meta := _read_meta(golden)
	var ref := Image.load_from_file(golden) if FileAccess.file_exists(golden) else null
	if ref == null or meta.is_empty():
		_fail("FAIL golden %s (or its .json) missing - create it with --update-golden" % golden)
		return
	if meta.get("scene", "") != scene_path or meta.get("size", "") != "%dx%d" % [want.x, want.y]:
		_fail("FAIL golden %s is for %s at %s, not %s at %dx%d"
				% [golden, meta.get("scene", "?"), meta.get("size", "?"), scene_path, want.x, want.y])
		return
	for k in who:
		if str(meta.get(k, "")) != who[k]:
			print("golden: SKIPPED compare - %s differs: golden '%s', this run '%s'" % [k, meta.get(k, ""), who[k]])
			return
	ref.convert(Image.FORMAT_RGBA8)
	var m := img.compute_image_metrics(ref, false)
	var rmse := float(m["root_mean_squared"])
	print("golden: rmse=%.3f max=%d (limit rmse %.3f)" % [rmse, int(m["max"]), max_rmse])
	if rmse > max_rmse:
		_fail("FAIL differs from golden %s: rmse %.3f > %.3f" % [golden, rmse, max_rmse])


func _write_golden(img: Image, golden: String, scene_path: String, want: Vector2i, who: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(golden.get_base_dir())
	var err := img.save_png(golden)
	var f := FileAccess.open(golden.get_basename() + ".json", FileAccess.WRITE)
	if err != OK or f == null:
		_fail("FAIL cannot write golden %s" % golden)
		return
	var meta := {"scene": scene_path, "size": "%dx%d" % [want.x, want.y]}
	meta.merge(who)
	f.store_string(JSON.stringify(meta, "  ") + "\n")
	print("golden: wrote %s (+ .json)" % golden)


func _read_meta(golden: String) -> Dictionary:
	var p := golden.get_basename() + ".json"
	if not FileAccess.file_exists(p):
		return {}
	var d = JSON.parse_string(FileAccess.get_file_as_string(p))
	return d if d is Dictionary else {}


func _fail(line: String) -> void:
	_failed = true
	print(line)


func _finish(line: String) -> void:
	if line.begins_with("FAIL"):
		_failed = true
	if not line.is_empty():
		print(line)
	quit(1 if _failed else 0)
