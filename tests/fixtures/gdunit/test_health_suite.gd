extends GdUnitTestSuite


func test_damage_clamps_at_zero() -> void:
	var h: Health = auto_free(Health.new())
	add_child(h)
	h.damage(150)
	assert_int(h.hp).is_equal(0)


func test_heal_does_not_revive() -> void:
	var h: Health = auto_free(Health.new())
	add_child(h)
	h.damage(h.max_hp)
	h.heal(10)
	assert_int(h.hp).is_equal(0)
