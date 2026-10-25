extends SceneTree

# Screenshot probe for measure_traps.sh (S1-S9), run as `--script` on a demo copy. It grabs the root viewport the way
# a naive capture would, and prints what came back instead of judging it.
#   user args: --scene=res://... --out=<png> [--frames=N] [--no-post-draw]

func _initialize() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else ""
	change_scene_to_packed(load(args.get("scene", "res://src/main.tscn")))
	print("probe: display=%s driver=%s" % [DisplayServer.get_name(), RenderingServer.get_current_rendering_driver_name()])
	for i in int(args.get("frames", "10")):
		await process_frame
	if not args.has("no-post-draw"):
		await RenderingServer.frame_post_draw
	var tex := root.get_texture()
	var img := tex.get_image() if tex else null
	if img == null:
		print("probe: image NULL")
	else:
		img.convert(Image.FORMAT_RGBA8)
		var flat := Image.create(img.get_width(), img.get_height(), false, Image.FORMAT_RGBA8)
		flat.fill(img.get_pixel(0, 0))
		var uniform := float(img.compute_image_metrics(flat, false)["max"]) == 0.0
		print("probe: image %dx%d uniform=%s pixel0=%s" % [img.get_width(), img.get_height(), uniform, img.get_pixel(0, 0)])
		if args.has("out"):
			img.save_png(args["out"])
	print("probe: done")
	quit()
