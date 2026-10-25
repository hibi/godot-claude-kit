extends Node

## Example two-process harness: a REAL server and a REAL client of src/net/net_match.tscn, each a headless engine.
##
##   bash <godot-multiplayer-harness skill>/net_run.sh --path . res://tools/netdiag_hits.tscn
##
## ONE scene plays both roles; net_run.sh passes `-- --role=server|client --port=N --clients=N`. Same scene means the
## same node paths on both sides - an RPC to a path the other side does not have is dropped, with the error only in
## the RECEIVER's log.
##
## Contract (skill godot-multiplayer-harness):
##   - one line per check: "  ok    <name>" or "  FAIL  <name> (<why>)"
##   - each role asserts what it RECEIVED (the synced value, the requests that arrived), never just what it sent
##   - every network wait has its own short timeout and also ends on the failure signals
##   - the server prints its banner only after every client reported done
##   - banners "NETDIAG-HITS-SERVER: PASS n/n" / "NETDIAG-HITS-CLIENT: PASS n/n", each after EVERY check of that role

const MATCH := preload("res://src/net/net_match.tscn")
## Seconds for one network wait. ENet's own limits are far longer: a client with no server gets connection_failed
## after ~31 s, a client whose server died hears server_disconnected after ~10 s.
const WAIT := 10.0
## Checks per role, not counting "all checks ran". Update them whenever you add or remove a check.
const EXPECTED := {"server": 6, "client": 3}

var role := ""
var port := 0
var clients := 1
var _ran := 0
var _failed := 0
var _done := 0          # server: clients that reported done
var _lost := false      # client: connection failed or server gone
var _synced: Array[int] = []
var _match: Node


func _check(what: String, cond: bool, why := "") -> void:
	_ran += 1
	if cond:
		print("  ok    %s" % what)
	else:
		_failed += 1
		print("  FAIL  %s (%s)" % [what, why])


## Polls cond every frame for at most `seconds`. A plain `await signal` would hang until ENet's own timeout.
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
	_match = MATCH.instantiate()
	add_child(_match)
	match role:
		"server": await _server()
		"client": await _client()
		_: _check("role given", false, "pass --role=server|client after `--`, got %s" % OS.get_cmdline_user_args())
	var expected: int = EXPECTED.get(role, 0)
	_check("all checks ran", _ran == expected, "ran %d of %d" % [_ran, expected])
	var ok := _failed == 0
	print("NETDIAG-HITS-%s: %s %d/%d" % [role.to_upper(), "PASS" if ok else "FAIL", _ran - _failed, _ran])
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()  # tells the other side now, instead of after ENet's ~10 s timeout
	get_tree().quit(0 if ok else 1)


func _server() -> void:
	var err: Error = _match.host(port)
	_check("listening on port %d" % port, err == OK, "error %d - 20 means the port is taken" % err)
	if err != OK:
		return
	var joined := await _wait_until(func(): return multiplayer.get_peers().size() >= clients)
	_check("%d client(s) connected" % clients, joined, "%d of %d" % [multiplayer.get_peers().size(), clients])
	var all_done := await _wait_until(func(): return _done >= clients)
	_check("every client reported done", all_done, "%d of %d" % [_done, clients])
	# Each client sends 30 (accepted), 9999 (must be refused), then 1 (accepted).
	var hp: int = _match.target.hp
	_check("server applied exactly the valid hits", hp == maxi(100 - 31 * clients, 0), "hp=%d" % hp)
	_check("oversized hits refused", _match.hits_refused == clients, "refused=%d" % _match.hits_refused)
	_check("valid hits accepted", _match.hits_accepted == 2 * clients, "accepted=%d" % _match.hits_accepted)


func _client() -> void:
	multiplayer.connection_failed.connect(func(): _lost = true)
	multiplayer.server_disconnected.connect(func(): _lost = true)
	_match.hp_synced.connect(func(hp: int): _synced.append(hp))
	_match.join("127.0.0.1", port)
	var up := await _wait_until(func(): return _lost or _connected())
	_check("connected to the server", up and not _lost, "lost=%s" % _lost)
	if not up or _lost:
		return
	_match.request_hit.rpc_id(1, 30)
	var got := await _wait_until(func(): return _lost or _synced.size() >= 1)
	_check("server synced hp after a valid hit", got and _synced == [70], "synced=%s lost=%s" % [_synced, _lost])
	# The refused hit produces no sync at all, so follow it with a valid one: the next sync tells what happened.
	_match.request_hit.rpc_id(1, 9999)
	_match.request_hit.rpc_id(1, 1)
	got = await _wait_until(func(): return _lost or _synced.size() >= 2)
	_check("oversized hit refused (only the 1 landed)", got and _synced == [70, 69],
		"synced=%s lost=%s" % [_synced, _lost])
	_client_done.rpc_id(1)
	# Stay until the server closes the session: quitting right away can drop the queued "done" packet.
	await _wait_until(func(): return _lost, 3.0)


func _connected() -> bool:
	return multiplayer.multiplayer_peer != null \
		and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


@rpc("any_peer", "call_remote", "reliable")
func _client_done() -> void:
	_done += 1
