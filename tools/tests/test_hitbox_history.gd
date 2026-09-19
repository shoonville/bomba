extends TestCase


func _s(x: float) -> HitboxHistory.Sample:
	var s := HitboxHistory.Sample.new()
	s.head = Vector3(x, 1.6, 0)
	s.body_a = Vector3(x, 0.4, 0)
	s.body_b = Vector3(x, 1.4, 0)
	s.feet = Vector3(x, 0, 0)
	return s


func test_interpolates_between_ticks() -> void:
	var h := HitboxHistory.new()
	h.record(10, _s(0.0))
	h.record(11, _s(1.0))
	h.record(12, _s(2.0))
	assert_near(h.sample_at(10.5).head.x, 0.5)
	assert_near(h.sample_at(11.0).head.x, 1.0)
	assert_near(h.sample_at(11.75).body_a.x, 1.75)
	assert_eq(h.earliest_tick(), 10)
	assert_eq(h.latest_tick(), 12)


func test_clamps_out_of_range() -> void:
	var h := HitboxHistory.new()
	h.record(10, _s(0.0))
	h.record(11, _s(1.0))
	assert_near(h.sample_at(3.0).head.x, 0.0)
	assert_near(h.sample_at(50.0).head.x, 1.0)


func test_bridges_gaps_and_overwrites() -> void:
	var h := HitboxHistory.new()
	h.record(10, _s(0.0))
	h.record(14, _s(0.4))
	assert_near(h.sample_at(12.0).head.x, 0.2, 1e-5, "gap between 10 and 14 is bridged linearly")
	h.record(10, _s(0.1))
	assert_near(h.sample_at(10.0).head.x, 0.1, 1e-5, "resimulated tick overwrites")


func test_teleport_is_not_interpolated() -> void:
	var h := HitboxHistory.new()
	h.record(10, _s(0.0))
	h.record(11, _s(30.0))
	assert_near(h.sample_at(10.4).head.x, 0.0, 1e-5, "before the midpoint: old spot")
	assert_near(h.sample_at(10.6).head.x, 30.0, 1e-5, "after the midpoint: new spot")


func test_capacity_trims() -> void:
	var h := HitboxHistory.new()
	h.capacity = 8
	for t in 20:
		h.record(t, _s(float(t)))
	assert_eq(h.earliest_tick(), 12)
	assert_eq(h.latest_tick(), 19)
	assert_false(h.has(5))
