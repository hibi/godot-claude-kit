extends SceneTree

## Network probe for measure_traps.sh (traps N1-N7). Copied into a demo copy as res://_net_probe.gd and run with
##   godot --headless --path <copy> --script res://_net_probe.gd -- --role=<role> --port=N [--root=Name]
## Roles:
##   server    listen; answer ping with pong; quit when the client leaves
##   client    ping the server, then call .rpc() on a function WITHOUT @rpc and rpc_id() with an unknown name
##   idle      connect and wait; report server_disconnected
##   noserver  connect to a port nobody listens on; report connection_failed
##   busy      create_server twice on the same port in one process

var args := {}
var t0 := 0


class ProbeNode extends Node:
	var tag := ""
	var pongs := 0

	@rpc("any_peer", "call_remote", "reliable")
	func ping(n: int) -> void:
		print("%s ping(%d) arrived" % [tag, n])
		pong.rpc_id(multiplayer.get_remote_sender_id(), n + 1)

	@rpc("authority", "call_remote", "reliable")
	func pong(n: int) -> void:
		pongs += 1
		print("%s pong(%d) arrived" % [tag, n])

	@rpc("any_peer", "call_remote", "reliable")
	func bye() -> void:
		print("%s bye arrived" % tag)

	func not_an_rpc() -> void:
		print("%s not_an_rpc RAN" % tag)


func ms() -> int:
	return Time.get_ticks_msec() - t0


func _initialize() -> void:
	t0 = Time.get_ticks_msec()
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=")
		args[kv[0]] = kv[1] if kv.size() > 1 else ""
	var role: String = args.get("role", "")
	var port := int(args.get("port", "0"))
	var node := ProbeNode.new()
	node.name = args.get("root", "Probe")
	node.tag = "[%s]" % role
	root.add_child(node)
	var mp := get_multiplayer()
	var peer := ENetMultiplayerPeer.new()
	peer.set_bind_ip("127.0.0.1")
	match role:
		"server":
			print("[server] create_server = %d" % peer.create_server(port))
			mp.multiplayer_peer = peer
			mp.peer_connected.connect(func(_id): print("[server] peer_connected at %d ms" % ms()))
			mp.peer_disconnected.connect(func(_id): print("[server] peer_disconnected at %d ms" % ms()); quit())
		"client":
			peer.create_client("127.0.0.1", port)
			mp.multiplayer_peer = peer
			await mp.connected_to_server
			print("[client] connected_to_server at %d ms" % ms())
			node.ping.rpc_id(1, 41)
			await create_timer(0.5).timeout
			node.not_an_rpc.rpc()
			node.rpc_id(1, "no_such_method")
			await create_timer(0.5).timeout
			node.bye.rpc_id(1)
			await create_timer(0.3).timeout
			print("[client] finished normally, pongs received: %d" % node.pongs)
			quit()
		"idle":
			peer.create_client("127.0.0.1", port)
			mp.multiplayer_peer = peer
			mp.connected_to_server.connect(func(): print("[idle] connected at %d ms" % ms()))
			mp.server_disconnected.connect(func(): print("[idle] server_disconnected at %d ms" % ms()); quit())
		"noserver":
			peer.create_client("127.0.0.1", port)
			mp.multiplayer_peer = peer
			mp.connection_failed.connect(func(): print("[noserver] connection_failed at %d ms" % ms()); quit())
		"busy":
			var second := ENetMultiplayerPeer.new()
			second.set_bind_ip("127.0.0.1")
			print("[busy] first create_server = %d" % peer.create_server(port))
			print("[busy] second create_server = %d" % second.create_server(port))
			quit()
