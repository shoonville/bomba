extends TestCase


func test_all_tables_load() -> void:
	var tables := TuningLoader.load_dir("res://tuning")
	for name in ["movement", "weapons", "arena", "net", "bots", "palette"]:
		assert_true(tables.has(name), "table %s" % name)
		assert_false((tables.get(name, {}) as Dictionary).is_empty(), "table %s non-empty" % name)


func test_lookup() -> void:
	var tables := TuningLoader.load_dir("res://tuning")
	assert_eq(int(TuningLoader.lookup(tables, "weapons.sniper.scope_in_ticks")), 16)
	assert_eq(TuningLoader.lookup(tables, "nope.nothing", "dflt"), "dflt")
	assert_eq(int(TuningLoader.lookup(tables, "net.tickrate")), 60)


func test_scope_in_ticks_matches_project_tickrate() -> void:
	# The animation is authored to this value; it must be a whole number of ticks at 60 Hz.
	var tables := TuningLoader.load_dir("res://tuning")
	var ticks: float = TuningLoader.lookup(tables, "weapons.sniper.scope_in_ticks")
	assert_near(ticks, floorf(ticks), 0.0, "scope_in_ticks must be an integer tick count")
	assert_eq(int(ProjectSettings.get_setting("netfox/time/tickrate")), 60)
	assert_eq(int(ProjectSettings.get_setting("physics/common/physics_ticks_per_second")), 60)


func test_player_palette_under_ceiling() -> void:
	var tables := TuningLoader.load_dir("res://tuning")
	var ceiling: float = TuningLoader.lookup(tables, "palette.value_ceiling")
	var players: Array = TuningLoader.lookup(tables, "palette.players")
	assert_eq(players.size(), 6)
	var hues := []
	for p in players:
		var hsv: Array = p["hsv"]
		assert_true(float(hsv[2]) <= ceiling, "player value under ceiling")
		assert_true(float(hsv[1]) >= 0.5 and float(hsv[1]) <= 0.9, "player saturation 0.5-0.9")
		hues.append(float(hsv[0]))
	hues.sort()
	for i in hues.size():
		var a: float = hues[i]
		var b: float = hues[(i + 1) % hues.size()]
		var gap: float = fmod(b - a + 360.0, 360.0)
		assert_true(gap >= 40.0, "hue gap %.0f between %.0f and %.0f" % [gap, a, b])
