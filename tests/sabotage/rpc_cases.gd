## Edge cases for rpc_check.sh: exactly the three lines marked BAD must FAIL (measure_traps.sh, KIT rpc). The run puts
## tests/sabotage/rpc_addon.gd into addons/ next to it - it declares addon_method and makes a bad call of its own.
extends Node

@rpc("any_peer") func same_line() -> void:
	pass

@rpc("any_peer")
@warning_ignore("unused_parameter")
func after_other_annotation(x: int) -> void:
	pass

func plain() -> void:
	pass

func configured() -> void:
	pass

func _ready() -> void:
	rpc_config("configured", {"rpc_mode": MultiplayerAPI.RPC_MODE_ANY_PEER})

func send(node: Node, method: String) -> void:
	same_line.rpc()                          # ok: same-line @rpc
	after_other_annotation.rpc_id(1, 5)      # ok: annotation stack
	node.rpc("same_line")                    # ok: object form
	node.rpc(&"same_line")                   # ok: StringName literal
	rpc_id(1, "after_other_annotation", 2)   # ok: bare object form
	configured.rpc()                         # ok: declared by rpc_config(), no annotation
	node.rpc("addon_method")                 # ok: @rpc in addons/
	plain.rpc()                              # BAD: callable form, no @rpc
	node.rpc_id(1, "no_such_method")         # BAD: object form, unknown
	rpc("plain")                             # BAD: bare, no @rpc
	node.rpc(method)                         # skipped: not known statically
	# plain.rpc() in a comment must not count
	print("plain.rpc() in a string")        # must not count: inside a string
