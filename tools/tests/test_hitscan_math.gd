extends TestCase


func test_ray_sphere() -> void:
	assert_near(HitscanMath.ray_sphere(Vector3.ZERO, Vector3.FORWARD, Vector3(0, 0, -10), 1.0), 9.0)
	assert_eq(HitscanMath.ray_sphere(Vector3.ZERO, Vector3.FORWARD, Vector3(0, 5, -10), 1.0), -1.0)
	assert_eq(HitscanMath.ray_sphere(Vector3.ZERO, Vector3.FORWARD, Vector3(0, 0, 10), 1.0), -1.0, "behind")
	assert_eq(HitscanMath.ray_sphere(Vector3.ZERO, Vector3.FORWARD, Vector3(0.5, 0, 0), 1.0), 0.0, "inside")


func test_ray_capsule_side_and_caps() -> void:
	var a := Vector3(0, 0.4, -10)
	var b := Vector3(0, 1.4, -10)
	assert_near(HitscanMath.ray_capsule(Vector3(0, 0.9, 0), Vector3.FORWARD, a, b, 0.3), 9.7, 1e-4, "side hit")
	assert_near(HitscanMath.ray_capsule(Vector3(0, 1.6, 0), Vector3.FORWARD, a, b, 0.3), 9.7 + (0.3 - sqrt(0.09 - 0.04)) , 1e-3, "top cap")
	assert_eq(HitscanMath.ray_capsule(Vector3(0, 2.0, 0), Vector3.FORWARD, a, b, 0.3), -1.0, "over the top")
	assert_eq(HitscanMath.ray_capsule(Vector3(1, 0.9, 0), Vector3.FORWARD, a, b, 0.3), -1.0, "beside")
	assert_eq(HitscanMath.ray_capsule(Vector3(0, 0.9, -10), Vector3.FORWARD, a, b, 0.3), 0.0, "inside")


func test_ray_capsule_parallel_axis() -> void:
	var a := Vector3(0, 0.4, -10)
	var b := Vector3(0, 1.4, -10)
	# Shooting straight down onto the top cap.
	assert_near(HitscanMath.ray_capsule(Vector3(0, 5, -10), Vector3.DOWN, a, b, 0.3), 5.0 - 1.7, 1e-4)
	assert_eq(HitscanMath.ray_capsule(Vector3(1, 5, -10), Vector3.DOWN, a, b, 0.3), -1.0)


func test_offset_direction() -> void:
	var d := HitscanMath.offset_direction(Vector3.FORWARD, 0.0, 10.0)
	assert_gt(d.y, 0.0, "positive pitch aims up")
	assert_near(d.length(), 1.0)
	var y := HitscanMath.offset_direction(Vector3.FORWARD, 10.0, 0.0)
	assert_lt(y.x, 0.0, "positive yaw turns left (counter-clockwise from above)")
	assert_near(HitscanMath.offset_direction(Vector3.FORWARD, 0, 0).distance_to(Vector3.FORWARD), 0.0, 1e-6)


func test_spread_deterministic_and_bounded() -> void:
	var a := HitscanMath.spread_offset(SeededRng.make_tick(1, "s", 10, 2), 3.5)
	var b := HitscanMath.spread_offset(SeededRng.make_tick(1, "s", 10, 2), 3.5)
	assert_near(a.x, b.x, 0.0)
	assert_near(a.y, b.y, 0.0)
	for i in 200:
		var o := HitscanMath.spread_offset(SeededRng.make_tick(1, "s", i, 2), 3.5)
		assert_true(o.length() <= 3.5 + 1e-6)
	assert_eq(HitscanMath.spread_offset(SeededRng.make_tick(1, "s", 1, 1), 0.0), Vector2.ZERO)
