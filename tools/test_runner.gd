extends SceneTree
## Headless unit test runner.
##   /Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script tools/test_runner.gd
## Compiles every project script (not addons), then runs every test_* method in tools/tests/test_*.gd.
## Exit code 1 on any failure.

const SKIP_DIRS := ["res://addons", "res://.godot", "res://reference"]


func _initialize() -> void:
	var t0 := Time.get_ticks_msec()
	print("=== BOMBA test runner | Godot %s ===" % Engine.get_version_info()["string"])
	var autoloads := []
	for n in ["Tuning", "Rng", "Log", "NetworkTime"]:
		autoloads.append("%s=%s" % [n, root.get_node_or_null(n) != null])
	print("autoloads: %s" % " ".join(autoloads))

	var compile_failed := 0
	var scripts := _find_scripts("res://")
	for path in scripts:
		var s := load(path)
		if s == null or not (s is GDScript) or not (s as GDScript).can_instantiate() and (s as GDScript).get_instance_base_type() == "":
			print("COMPILE FAIL %s" % path)
			compile_failed += 1
	print("compiled %d scripts, %d failed" % [scripts.size(), compile_failed])

	var total := 0
	var failed := 0
	var asserts := 0
	var test_scripts := _find_scripts("res://tools/tests").filter(func(p: String): return p.get_file().begins_with("test_"))
	test_scripts.sort()
	for tp in test_scripts:
		var script: GDScript = load(tp)
		if script == null:
			print("LOAD FAIL %s" % tp)
			failed += 1
			continue
		var raw = script.new()
		if not (raw is TestCase):
			continue
		var inst: TestCase = raw
		var methods := []
		for m in inst.get_method_list():
			if str(m["name"]).begins_with("test_"):
				methods.append(str(m["name"]))
		methods.sort()
		for name in methods:
			total += 1
			inst._current = name
			var before: int = inst._failures.size()
			inst.setup()
			inst.call(name)
			inst.teardown()
			if inst._failures.size() > before:
				failed += 1
				for i in range(before, inst._failures.size()):
					print("FAIL %s::%s" % [tp.get_file(), inst._failures[i]])
			else:
				print("ok   %s::%s" % [tp.get_file(), name])
		asserts += inst._asserts

	var ms := Time.get_ticks_msec() - t0
	print("=== %d tests, %d failed, %d assertions, %d scripts compiled (%d failed), %d ms ===" % [total, failed, asserts, scripts.size(), compile_failed, ms])
	quit(1 if (failed > 0 or compile_failed > 0) else 0)


func _find_scripts(dir_path: String) -> Array:
	var out := []
	for skip in SKIP_DIRS:
		if dir_path.begins_with(skip):
			return out
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		var full := dir_path.path_join(entry)
		if dir.current_is_dir():
			if not entry.begins_with("."):
				out.append_array(_find_scripts(full))
		elif entry.ends_with(".gd"):
			out.append(full)
		entry = dir.get_next()
	dir.list_dir_end()
	return out
