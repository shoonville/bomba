extends TestCase


func test_streams_reproducible() -> void:
	var a := SeededRng.make_stream(1234, "spawn")
	var b := SeededRng.make_stream(1234, "spawn")
	for i in 20:
		assert_eq(a.randi(), b.randi())


func test_streams_differ_by_name_and_seed() -> void:
	var a := SeededRng.make_stream(1234, "spawn")
	var b := SeededRng.make_stream(1234, "spread")
	var c := SeededRng.make_stream(4321, "spawn")
	assert_ne(a.randi(), b.randi())
	assert_ne(SeededRng.make_stream(1234, "spawn").randi(), c.randi())


func test_tick_streams_same_per_tick_and_peer() -> void:
	var first := SeededRng.make_tick(77, "sniper_hip", 120, 2).randf()
	var again := SeededRng.make_tick(77, "sniper_hip", 120, 2).randf()
	var other_tick := SeededRng.make_tick(77, "sniper_hip", 121, 2).randf()
	var other_peer := SeededRng.make_tick(77, "sniper_hip", 120, 3).randf()
	assert_near(first, again, 0.0)
	assert_ne(first, other_tick)
	assert_ne(first, other_peer)
