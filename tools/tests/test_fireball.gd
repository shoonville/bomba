extends TestCase
## FIREBALL: the ball's maths (FireballSim), the platform layout and the manifest's enabled flag.

var cfg: Dictionary


func setup() -> void:
	cfg = TuningLoader.load_file("res://tuning/fireball.json")


func _sample(feet: Vector3) -> HitboxHistory.Sample:
	var mc := MovementConfig.from_dict(TuningLoader.load_file("res://tuning/movement.json"))
	return Hitboxes.sample_from(feet, mc, true)


func test_reflect_goes_to_the_player_nearest_the_crosshair() -> void:
	var eye := Vector3(0, 1.6, 0)
	var aim := Vector3(0, 0, -1)
	var candidates := [
		{"id": 2, "point": Vector3(6.0, 1.1, -8.0)},     # 37° off
		{"id": 3, "point": Vector3(-1.0, 1.1, -12.0)},   # 5° off: the one
		{"id": 4, "point": Vector3(0.0, 1.1, 9.0)},      # behind
	]
	assert_eq(FireballSim.pick_reflect_target(eye, aim, candidates), 3)
	assert_eq(FireballSim.pick_reflect_target(eye, aim, []), 0, "nobody to send it to")


func test_speed_ramps_per_reflect_and_caps() -> void:
	var start := float(cfg["speed_start_m_s"])
	var gain := float(cfg["speed_gain_per_reflect_m_s"])
	assert_near(FireballSim.speed_for(0, cfg), start)
	assert_near(FireballSim.speed_for(3, cfg), start + 3.0 * gain)
	assert_near(FireballSim.speed_for(1000, cfg), float(cfg["speed_max_m_s"]))
	assert_true(FireballSim.speed_for(1, cfg) > FireballSim.speed_for(0, cfg), "faster after a reflect")


func test_steer_turns_by_at_most_the_limit() -> void:
	var dir := Vector3(0, 0, -1)
	var to := Vector3(1, 0, 0)
	var turned := FireballSim.steer(dir, to, deg_to_rad(10.0))
	assert_near(rad_to_deg(dir.angle_to(turned)), 10.0, 1e-3)
	assert_near(turned.length(), 1.0, 1e-6)
	var reached := FireballSim.steer(dir, Vector3(0.1, 0, -1).normalized(), deg_to_rad(10.0))
	assert_vec_near(reached, Vector3(0.1, 0, -1).normalized(), 1e-5, "inside the limit: straight at it")
	var back := FireballSim.steer(dir, Vector3(0, 0, 1), deg_to_rad(10.0))
	assert_near(rad_to_deg(dir.angle_to(back)), 10.0, 1e-3, "straight behind still turns")


func test_segment_distance() -> void:
	assert_near(FireballSim.segment_distance(Vector3(0, 0, 0), Vector3(2, 0, 0), Vector3(1, 1, 0), Vector3(1, 3, 0)), 1.0, 1e-6)
	assert_near(FireballSim.segment_distance(Vector3(0, 0, 0), Vector3(2, 0, 0), Vector3(1, -1, 0), Vector3(1, 1, 0)), 0.0, 1e-6, "crossing")
	assert_near(FireballSim.segment_distance(Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(3, 0, 0), Vector3(4, 0, 0)), 2.0, 1e-6, "collinear, apart")
	assert_near(FireballSim.segment_distance(Vector3(0, 0, 0), Vector3(0, 0, 0), Vector3(0, 2, 0), Vector3(0, 2, 0)), 2.0, 1e-6, "two points")


func test_ball_step_hits_a_body_and_misses_wide() -> void:
	var s := _sample(Vector3(5, 0, 0))
	var r := float(cfg["ball_radius_m"])
	assert_true(FireballSim.step_hits(Vector3(5, 1.0, -3), Vector3(5, 1.0, 3), r, s), "through the chest")
	assert_true(FireballSim.step_hits(Vector3(5, 1.62, -0.8), Vector3(5, 1.62, -0.6), r, s), "clipping the head")
	assert_false(FireballSim.step_hits(Vector3(8, 1.0, -3), Vector3(8, 1.0, 3), r, s), "3 m to the side")
	assert_false(FireballSim.step_hits(Vector3(5, 4.0, -3), Vector3(5, 4.0, 3), r, s), "over the head")


func test_guard_takes_a_ball_in_front_not_behind() -> void:
	var eye := Vector3(0, 1.62, 0)
	var aim := Vector3(0, 0, -1)
	var range_m := float(cfg["parry_range_m"])
	var cone := deg_to_rad(float(cfg["parry_cone_deg"]))
	assert_true(FireballSim.step_guarded(Vector3(0.5, 1.4, -2.5), Vector3(0.5, 1.4, -2.0), eye, aim, range_m, cone), "in front, in range")
	assert_false(FireballSim.step_guarded(Vector3(0.5, 1.4, 2.5), Vector3(0.5, 1.4, 2.0), eye, aim, range_m, cone), "behind")
	assert_false(FireballSim.step_guarded(Vector3(0, 1.4, -6.0), Vector3(0, 1.4, -5.5), eye, aim, range_m, cone), "too far")
	assert_true(FireballSim.step_guarded(Vector3(-4, 1.4, -2.0), Vector3(4, 1.4, -2.0), eye, aim, range_m, cone), "crossing in front: the closest point counts")


func test_platform_spawns_evenly_facing_the_centre() -> void:
	for seats in [2, 3, 6]:
		var layout := PlatformLayout.build(cfg, seats)
		var spawns: Array = layout["spawns"]
		assert_eq(spawns.size(), seats, "one spawn per seat")
		var spawn_r := float(cfg["spawn_radius_m"])
		for i in spawns.size():
			var p: Vector3 = spawns[i]["pos"]
			assert_near(Vector2(p.x, p.z).length(), spawn_r, 1e-4, "on the ring")
			var fwd := MovementModel.forward_from_yaw(float(spawns[i]["yaw"]))
			assert_near(fwd.dot(-p.normalized()), 1.0, 1e-4, "facing the centre")
			var q: Vector3 = spawns[(i + 1) % spawns.size()]["pos"]
			var gap := Vector2(p.x, p.z).angle_to(Vector2(q.x, q.z))
			assert_near(absf(gap), TAU / float(seats), 1e-4, "evenly spaced")
	var layout := PlatformLayout.build(cfg, 4)
	var top: Dictionary = layout["boxes"][0]
	assert_eq(str(top["shape"]), "cylinder")
	assert_near(float((top["size"] as Vector3).x), float(cfg["platform_radius_m"]) * 2.0, 1e-6)
	assert_near(float((top["pos"] as Vector3).y) + float((top["size"] as Vector3).y) * 0.5, 0.0, 1e-6, "its top at y = 0")


func test_manifest_enabled_flag_parks_a_minigame() -> void:
	var off := MinigameManifest.from_json({"id": "x", "enabled": false}, "res://minigames/x")
	assert_false(off.enabled)
	var on := MinigameManifest.from_json({"id": "y"}, "res://minigames/y")
	assert_true(on.enabled, "on by default")
	MinigameRegistry.scan(true)
	var arena := MinigameRegistry.get_manifest("arena")
	var snipers := MinigameRegistry.get_manifest("snipers")
	var fireball := MinigameRegistry.get_manifest("fireball")
	var last_stand := MinigameRegistry.get_manifest("last_stand")
	assert_true(arena != null and not arena.enabled, "ARENA parked")
	assert_true(snipers != null and not snipers.enabled, "SNIPERS parked")
	assert_true(fireball != null and fireball.enabled, "FIREBALL on")
	assert_true(last_stand != null and last_stand.enabled, "LAST STAND on")
	assert_eq(fireball.weapons.size(), 1)
	assert_eq(fireball.weapons[0], "katana")
	assert_eq(fireball.scoring, "survival")
