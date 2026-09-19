extends TestCase


func _buf() -> SnapshotBuffer:
	var b := SnapshotBuffer.new()
	b.interp_delay_ticks = 6.0
	b.extrapolate_max_ticks = 2.0
	b.snap_distance = 2.0
	return b


func test_interpolates_behind_latest() -> void:
	var b := _buf()
	for t in 20:
		b.push(t, Vector3(t, 0, 0), 0.0, 0.0)
	b.advance(0.0)
	assert_near(b.render_tick(), 13.0)
	var s := b.sample()
	assert_true(s.valid)
	assert_near(s.origin.x, 13.0)
	b.advance(0.5)
	assert_near(b.sample().origin.x, 13.5, 1e-4)


func test_rate_adjusts_instead_of_jumping() -> void:
	var b := _buf()
	for t in 20:
		b.push(t, Vector3(t, 0, 0), 0.0, 0.0)
	b.advance(0.0)
	for t in range(20, 30):
		b.push(t, Vector3(t, 0, 0), 0.0, 0.0)
	# target moved by 10 ticks; one frame of 1 tick may only move by at most 1.1 ticks
	b.advance(1.0)
	assert_true(b.render_tick() <= 14.1 + 1e-6 and b.render_tick() >= 14.0, "render tick %f" % b.render_tick())


func test_extrapolation_is_capped() -> void:
	var b := _buf()
	b.interp_delay_ticks = 0.0
	b.push(0, Vector3(0, 0, 0), 0.0, 0.0)
	b.push(1, Vector3(1, 0, 0), 0.0, 0.0)
	b.advance(0.0)
	b.advance(1.0)
	var s := b.sample()
	assert_true(s.extrapolated)
	assert_near(s.origin.x, 2.0, 1e-4)
	b.advance(5.0)
	var s2 := b.sample()
	assert_near(s2.origin.x, 3.0, 1e-4, "capped at 2 ticks of extrapolation")
	assert_true(s2.starved)


func test_teleport_snaps() -> void:
	var b := _buf()
	b.interp_delay_ticks = 0.5
	b.push(0, Vector3(0, 0, 0), 0.0, 0.0)
	b.push(1, Vector3(50, 0, 0), 0.0, 0.0)
	b.advance(0.0)
	var s := b.sample()
	assert_true(s.origin.x == 0.0 or s.origin.x == 50.0, "never half way across a respawn: %f" % s.origin.x)


func test_yaw_wraps() -> void:
	var b := _buf()
	b.interp_delay_ticks = 0.5
	b.push(0, Vector3.ZERO, deg_to_rad(170.0), 0.0)
	b.push(1, Vector3.ZERO, deg_to_rad(-170.0), 0.0)
	b.advance(0.0)
	var s := b.sample()
	assert_near(absf(rad_to_deg(s.yaw)), 180.0, 1e-3, "shortest path through 180")
