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
