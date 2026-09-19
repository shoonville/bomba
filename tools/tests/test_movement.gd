extends TestCase

var cfg: MovementConfig
const DT := 1.0 / 60.0


func setup() -> void:
	cfg = MovementConfig.from_dict(TuningLoader.load_file("res://tuning/movement.json"))


func _run(ticks: int, wish: Vector2, jump_at: int = -1, floor_until: int = 1 << 30) -> Array:
	# Integrates in free space: on_floor while y <= 0 (or forced), gravity applies in the air.
	var v := Vector3.ZERO
	var pos := Vector3.ZERO
	var jb := 0
	var coy := 0
	var max_y := 0.0
	var air_ticks := 0
	for t in ticks:
		var on_floor := pos.y <= 0.0001 and v.y <= 0.0 and t < floor_until
		var r := MovementModel.step(v, on_floor, wish, 0.0, t == jump_at, jb, coy, DT, cfg)
		v = r.velocity
		jb = r.jump_buffer
		coy = r.coyote
		pos += v * DT
		if pos.y < 0.0 and not on_floor:
			pos.y = 0.0
			v.y = 0.0
		if pos.y > 0.0:
			air_ticks += 1
		max_y = maxf(max_y, pos.y)
	return [v, pos, max_y, air_ticks]


func test_deterministic() -> void:
	var a := _run(300, Vector2(0.3, 1.0), 40)
	var b := _run(300, Vector2(0.3, 1.0), 40)
	assert_vec_near(a[0], b[0], 0.0)
	assert_vec_near(a[1], b[1], 0.0)


func test_reaches_walk_speed_and_stops() -> void:
	var r := _run(120, Vector2(0, 1))
	var v: Vector3 = r[0]
	assert_near(Vector3(v.x, 0, v.z).length(), cfg.walk_speed, 0.01, "walk speed reached")
	assert_near(v.z, -cfg.walk_speed, 0.01, "forward is -Z")
	var stop := _run(60, Vector2.ZERO)
	assert_near(stop[0].length(), 0.0, 0.0)


func test_acceleration_is_gradual() -> void:
	var v := Vector3.ZERO
	var r := MovementModel.step(v, true, Vector2(0, 1), 0.0, false, 0, 0, DT, cfg)
	assert_lt(r.velocity.length(), cfg.walk_speed * 0.5, "one tick is not full speed")
	assert_gt(r.velocity.length(), 0.0)


func test_jump_height_and_air_time() -> void:
	var r := _run(240, Vector2.ZERO, 10)
	var expected_h := cfg.jump_velocity * cfg.jump_velocity / (2.0 * cfg.gravity)
	assert_near(r[2], expected_h, 0.08, "apex %.2f vs %.2f" % [r[2], expected_h])
	var expected_air := 2.0 * cfg.jump_velocity / cfg.gravity
	assert_near(float(r[3]) * DT, expected_air, 0.06, "air time")
	assert_gt(expected_air, 0.9, "floaty: nearly a second in the air")


func test_jump_buffer_fires_on_landing() -> void:
	# Press jump 3 ticks before landing: buffer must carry it.
	var v := Vector3(0, -3, 0)
	var r1 := MovementModel.step(v, false, Vector2.ZERO, 0.0, true, 0, 0, DT, cfg)
	assert_false(r1.jumped)
	assert_eq(r1.jump_buffer, cfg.jump_buffer_ticks)
	var r2 := MovementModel.step(r1.velocity, false, Vector2.ZERO, 0.0, false, r1.jump_buffer, r1.coyote, DT, cfg)
	var r3 := MovementModel.step(r2.velocity, true, Vector2.ZERO, 0.0, false, r2.jump_buffer, r2.coyote, DT, cfg)
	assert_true(r3.jumped, "buffered jump fires on landing")
	assert_near(r3.velocity.y, cfg.jump_velocity)


func test_coyote_time() -> void:
	var r := MovementModel.step(Vector3.ZERO, true, Vector2.ZERO, 0.0, false, 0, 0, DT, cfg)
	assert_eq(r.coyote, cfg.coyote_ticks)
	var r2 := MovementModel.step(r.velocity, false, Vector2.ZERO, 0.0, true, r.jump_buffer, r.coyote, DT, cfg)
	assert_true(r2.jumped, "jump within coyote window after leaving floor")


func test_air_control_weaker_than_ground() -> void:
	var g := MovementModel.step(Vector3.ZERO, true, Vector2(1, 0), 0.0, false, 0, 0, DT, cfg)
	var a := MovementModel.step(Vector3.ZERO, false, Vector2(1, 0), 0.0, false, 0, 0, DT, cfg)
	assert_gt(g.velocity.x, a.velocity.x * 2.0)


func test_backpedal_slower() -> void:
	var f := _run(120, Vector2(0, 1))
	var b := _run(120, Vector2(0, -1))
	assert_near(b[0].length(), cfg.walk_speed * cfg.backpedal_multiplier, 0.01)
	assert_gt(f[0].length(), b[0].length())
