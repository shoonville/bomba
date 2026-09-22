extends TestCase
## KING OF THE HILL's rules (minigames/hill/hill_rules.gd).


func test_inside_cylinder() -> void:
	var hill := Vector3(0, 9, 0)
	assert_true(HillRules.inside(Vector3(1.0, 9.0, 1.0), hill, 2.8, 3.0), "on the deck, inside")
	assert_true(HillRules.inside(Vector3(2.8, 9.0, 0.0), hill, 2.8, 3.0), "the rim counts")
	assert_false(HillRules.inside(Vector3(2.81, 9.0, 0.0), hill, 2.8, 3.0), "just past the rim")
	assert_true(HillRules.inside(Vector3(0, 11.9, 0), hill, 2.8, 3.0), "a jump inside the height")
	assert_false(HillRules.inside(Vector3(0, 12.1, 0), hill, 2.8, 3.0), "over the top")
	assert_true(HillRules.inside(Vector3(0, 8.75, 0), hill, 2.8, 3.0), "a step under the floor still counts")
	assert_false(HillRules.inside(Vector3(0, 0, 0), hill, 2.8, 3.0), "the ground under a raised hill does not")


func test_holder() -> void:
	assert_eq(HillRules.holder([]), HillRules.EMPTY, "empty")
	assert_eq(HillRules.holder([-3]), -3, "alone")
	assert_eq(HillRules.holder([1, -3]), HillRules.CONTESTED, "contested")


func test_order_visits_every_spot_and_never_repeats_the_last() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var seen := {}
	var last := -1
	for round in 20:
		var order := HillRules.make_order(8, rng, last)
		assert_eq(order.size(), 8, "a full permutation")
		var set := {}
		for i in order:
			set[int(i)] = true
		assert_eq(set.size(), 8, "every spot once")
		assert_ne(int(order[0]), last, "never the spot just left")
		for i in order:
			seen[int(i)] = true
		last = int(order[-1])
	assert_eq(seen.size(), 8)
	var pinned := HillRules.make_order(8, rng, 3, 3)
	assert_eq(int(pinned[0]), 3, "the harness pins the first spot")
	assert_eq(HillRules.make_order(1, rng, 0).size(), 1, "one spot is allowed to repeat")


func test_order_is_seeded() -> void:
	var a := RandomNumberGenerator.new()
	a.seed = 9
	var b := RandomNumberGenerator.new()
	b.seed = 9
	assert_eq(HillRules.make_order(8, a), HillRules.make_order(8, b), "same seed, same order")


func test_format_seconds() -> void:
	assert_eq(HillRules.format_seconds(0, 60), "0:00")
	assert_eq(HillRules.format_seconds(59 * 60 + 30, 60), "0:59")
	assert_eq(HillRules.format_seconds(61 * 60, 60), "1:01")
