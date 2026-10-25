extends SceneTree

## Holds a UDP port with a plain socket (not ENet) for --seconds, so a harness server cannot listen on it:
##   godot --headless --path <copy> --script res://_hold_udp_port.gd -- --port=N --seconds=S


func _initialize() -> void:
	var port := 0
	var seconds := 30.0
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=")
		if kv[0] == "port":
			port = int(kv[1])
		elif kv[0] == "seconds":
			seconds = float(kv[1])
	var udp := PacketPeerUDP.new()
	print("[hold] bind(%d) = %d" % [port, udp.bind(port, "127.0.0.1")])
	await create_timer(seconds).timeout
	udp.close()
	quit()
