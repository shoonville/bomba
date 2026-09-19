extends TestCase


func test_ranking_and_ties() -> void:
	var r := MinigameResult.new()
	r.add(1, 5, "a")
	r.add(-1, 9, "bot")
	r.add(2, 5, "b")
	r.add(3, 0, "c")
	r.finalize()
	assert_eq(r.winner_id(), -1)
	assert_eq(int(r.rankings[0]["rank"]), 1)
	assert_eq(int(r.rankings[1]["rank"]), 2)
	assert_eq(int(r.rankings[2]["rank"]), 2, "tie shares rank")
	assert_eq(int(r.rankings[3]["rank"]), 4)


func test_round_trip() -> void:
	var r := MinigameResult.new()
	r.minigame_id = "arena"
	r.add(1, 3, "a")
	r.finalize()
	var back := MinigameResult.from_dict(r.to_dict())
	assert_eq(back.minigame_id, "arena")
	assert_eq(back.winner_id(), 1)


func test_registry_finds_arena() -> void:
	var ids := MinigameRegistry.scan(true).keys()
	assert_true(ids.has("arena"), "arena manifest present: %s" % str(ids))
	assert_true(ids.has("snipers"), "second minigame found by folder scan alone")
	var sn := MinigameRegistry.get_manifest("snipers")
	assert_eq(sn.weapons, PackedStringArray(["sniper"]))
	assert_eq(sn.time_limit_seconds, 150)
	assert_true(ids.has("last_stand"), "third minigame found by folder scan alone")
	var ls := MinigameRegistry.get_manifest("last_stand")
	assert_eq(ls.scoring, "survival")
	assert_eq(ls.min_players, 2)
	assert_eq(ls.time_limit_seconds, 60)
	var m := MinigameRegistry.get_manifest("arena")
	if m != null:
		assert_eq(m.scene_path, "res://minigames/arena/minigame.tscn")
		assert_true(m.weapons.has("sniper"))


func _segment_hits_box(a: Vector3, b: Vector3, box: Dictionary) -> bool:
	# Slab test on the box shrunk by 0.45 m so a capsule brushing a corner does not count.
	var half: Vector3 = box["size"] * 0.5 - Vector3(0.45, 0.0, 0.45)
	var c: Vector3 = box["pos"]
	var lo := c - half
	var hi := c + half
	var d := b - a
	var t0 := 0.0
	var t1 := 1.0
	for i in 3:
		if absf(d[i]) < 1e-6:
			if a[i] < lo[i] or a[i] > hi[i]:
				return false
			continue
		var ta := (lo[i] - a[i]) / d[i]
		var tb := (hi[i] - a[i]) / d[i]
		t0 = maxf(t0, minf(ta, tb))
		t1 = minf(t1, maxf(ta, tb))
		if t0 > t1:
			return false
	return true


func _check_layout(name: String, layout: Dictionary) -> void:
	var wp: Array = layout["waypoints"]
	var floor_boxes := 0
	for e in layout["edges"]:
		var a: Vector3 = wp[int(e[0])] + Vector3(0, 0.9, 0)
		var b: Vector3 = wp[int(e[1])] + Vector3(0, 0.9, 0)
		for box in layout["boxes"]:
			if str(box["tone"]) == "floor":
				floor_boxes += 1
				continue
			# Steps and decks the edge climbs are allowed: only boxes taller than the edge's higher end count.
			var top: float = (box["pos"] as Vector3).y + (box["size"] as Vector3).y * 0.5
			if top <= maxf(a.y, b.y) - 0.9 + 1.3:
				continue
			assert_false(_segment_hits_box(a, b, box), "%s: edge %s-%s crosses box at %s" % [name, e[0], e[1], str(box["pos"])])
	assert_true(layout["spawns"].size() >= 6, "%s spawns" % name)
	var half: Vector2 = layout["size"] * 0.5
	for sp in layout["spawns"]:
		var p: Vector3 = sp["pos"]
		assert_true(absf(p.x) < half.x and absf(p.z) < half.y, "%s spawn inside walls: %s" % [name, str(p)])


func test_layouts_have_clear_waypoint_edges() -> void:
	_check_layout("graybox", GrayboxLayout.build())
	_check_layout("pit", PitLayout.build())
