extends GutTest


func test_damage_clamps_at_zero() -> void:
	var h := Health.new()
	add_child_autofree(h)
	h.damage(150)
	assert_eq(h.hp, 0, "hp after overkill")


func test_heal_does_not_revive() -> void:
	var h := Health.new()
	add_child_autofree(h)
	h.damage(h.max_hp)
	h.heal(10)
	assert_eq(h.hp, 0, "hp after healing a corpse")
