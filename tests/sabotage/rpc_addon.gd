## Third-party code for rpc_check.sh's edge cases (copied into addons/ by measure_traps.sh): its @rpc declaration must
## count, its own bad call must NOT be reported - addons are not the project's to fail.
extends Node

@rpc("any_peer")
func addon_method() -> void:
	pass

func addon_send() -> void:
	rpc("addon_has_no_such_method")
