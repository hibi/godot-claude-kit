extends Node

## Server-authoritative hits: a client only ASKS for damage, the server validates the request, applies it to the real
## Health and tells every client the new hp. Clients never write hp on their own.

signal hp_synced(hp: int)

## The largest hit the server accepts. A client can send any number, so the server is the one that checks.
const MAX_HIT := 50

var hits_accepted := 0
var hits_refused := 0

@onready var target: Health = $Target


## Loopback by default: a test never needs the LAN, and binding every interface makes Windows ask for a firewall
## exception on the first run.
func host(port: int, bind_ip := "127.0.0.1") -> Error:
	var peer := ENetMultiplayerPeer.new()
	peer.set_bind_ip(bind_ip)
	var err := peer.create_server(port)
	if err == OK:
		multiplayer.multiplayer_peer = peer
	return err


func join(address: String, port: int) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err == OK:
		multiplayer.multiplayer_peer = peer
	return err


## Client -> server.
@rpc("any_peer", "call_remote", "reliable")
func request_hit(amount: int) -> void:
	if not multiplayer.is_server():
		return
	if amount < 1 or amount > MAX_HIT:
		hits_refused += 1
		return
	hits_accepted += 1
	target.damage(amount)
	sync_hp.rpc(target.hp)


## Server -> clients.
@rpc("authority", "call_remote", "reliable")
func sync_hp(hp: int) -> void:
	target.hp = hp
	hp_synced.emit(hp)
