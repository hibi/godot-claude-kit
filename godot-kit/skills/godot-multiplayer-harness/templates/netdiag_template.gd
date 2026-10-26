extends Node

## NETDIAG-__NAME__: two-process headless harness - a REAL server and REAL client(s), each its own engine process.
##
##   bash <godot-multiplayer-harness skill>/net_run.sh --path . res://__DIR__/netdiag___name__.tscn
##   (never start the roles by hand: net_run.sh imports once, isolates every process, passes the role and port, and
##    judges EVERY process's log - an RPC error lands in one side's log only, and every exit code stays 0)
##
## ONE scene plays both roles (`-- --role=server|client --port=N --clients=N`), so both sides have the same node
## paths: an RPC to a path the other side does not have is dropped, and only the receiver's log says so.
##
## Contract (skill godot-multiplayer-harness):
##   - one line per check: "  ok    <name>" or "  FAIL  <name> (<why>)"
##   - each role asserts what it RECEIVED (a synced value, the requests that arrived), never only what it sent
##   - every network wait goes through _wait_until (short timeout, ends on the failure signals too)
##   - the server prints its banner only after every client reported done
##   - banners "NETDIAG-__NAME__-SERVER: PASS n/n" / "NETDIAG-__NAME__-CLIENT: PASS n/n", after EVERY check of the role
##
## Fresh from the template this harness FAILS on purpose, on both sides: replace the placeholders with real checks.

## Seconds for one network wait. ENet's own limits are far longer: a client with no server gets connection_failed
## after ~31 s, a client whose server died hears server_disconnected after ~10 s.
const WAIT := 10.0
## Checks per role, not counting "all checks ran". Update them whenever you add or remove a check.
const EXPECTED := {"server": 4, "client": 2}

var role := ""
var port := 0
var clients := 1
var _ran := 0
var _failed := 0
# Members, not locals: the signal lambdas below set them. A lambda captures a LOCAL by value, so `lost = true` on a
# local would change only the lambda's copy.
var _done := 0       # server: clients that reported done
var _lost := false   # client: connection failed or the server went away


func _check(what: String, cond: bool, why := "") -> void:
	_ran += 1
	if cond:
		print("  ok    %s" % what)
	else:
		_failed += 1
		print("  FAIL  %s (%s)" % [what, why])


## Polls cond every frame for at most `seconds`. A plain `await <signal>` would hang until ENet's own timeout.
func _wait_until(cond: Callable, seconds := WAIT) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000)
	while not cond.call():
		if Time.get_ticks_msec() > deadline:
			return false
		await get_tree().process_frame
	return true


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=")
		match kv[0]:
			"role": role = kv[1]
			"port": port = int(kv[1])
			"clients": clients = int(kv[1])
	# Instantiate the REAL game scene you test here, as a child, in BOTH roles (same path on both sides), e.g.:
	#   _game = preload("res://src/net/match.tscn").instantiate()
	#   add_child(_game)
	match role:
		"server": await _server()
		"client": await _client()
		_: _check("role given", false, "pass --role=server|client after `--`, got %s" % OS.get_cmdline_user_args())
	var expected: int = EXPECTED.get(role, 0)
	_check("all checks ran", _ran == expected, "ran %d of %d" % [_ran, expected])
	var ok := _failed == 0
	print("NETDIAG-__NAME__-%s: %s %d/%d" % [role.to_upper(), "PASS" if ok else "FAIL", _ran - _failed, _ran])
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()  # tells the other side now, instead of after ENet's ~10 s timeout
	get_tree().quit(0 if ok else 1)


func _server() -> void:
	var err := _host()
	_check("listening on port %d" % port, err == OK, "error %d - 20 means the port is taken" % err)
	if err != OK:
		return
	var joined := await _wait_until(func(): return multiplayer.get_peers().size() >= clients)
	_check("%d client(s) connected" % clients, joined, "%d of %d" % [multiplayer.get_peers().size(), clients])
	var all_done := await _wait_until(func(): return _done >= clients)
	_check("every client reported done", all_done, "%d of %d" % [_done, clients])
	# Assert what the server RECEIVED and applied, with the values in <why>, e.g.:
	#   _check("server applied the hit", _game.target.hp == 70, "hp=%d" % _game.target.hp)
	_check("placeholder replaced by real server checks", false, "fresh template - write the real checks first")


func _client() -> void:
	multiplayer.connection_failed.connect(func(): _lost = true)
	multiplayer.server_disconnected.connect(func(): _lost = true)
	_join()
	var up := await _wait_until(func(): return _lost or _connected())
	_check("connected to the server", up and not _lost, "lost=%s" % _lost)
	if not up or _lost:
		return
	# Drive the game from the client and assert what came BACK, waiting with _wait_until, e.g.:
	#   _game.request_hit.rpc_id(1, 30)
	#   var got := await _wait_until(func(): return _lost or _synced.size() >= 1)
	#   _check("server synced hp", got and _synced == [70], "synced=%s lost=%s" % [_synced, _lost])
	_check("placeholder replaced by real client checks", false, "fresh template - write the real checks first")
	_client_done.rpc_id(1)
	# Stay until the server closes the session: quitting right away can drop the queued "done" packet.
	await _wait_until(func(): return _lost, 3.0)


## Loopback only: a test never needs the LAN, and binding every interface makes Windows ask for a firewall exception.
## If your game has its own host()/join(), call those instead - then the harness tests them too.
func _host() -> Error:
	var peer := ENetMultiplayerPeer.new()
	peer.set_bind_ip("127.0.0.1")
	var err := peer.create_server(port)
	if err == OK:
		multiplayer.multiplayer_peer = peer
	return err


func _join() -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client("127.0.0.1", port)
	if err == OK:
		multiplayer.multiplayer_peer = peer
	return err


func _connected() -> bool:
	return multiplayer.multiplayer_peer != null \
		and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


@rpc("any_peer", "call_remote", "reliable")
func _client_done() -> void:
	_done += 1
