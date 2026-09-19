class_name MinigameRegistry
extends RefCounted
## Finds minigames by scanning res://minigames/*/manifest.json. Adding a minigame folder is the
## whole registration; nothing else in the project lists minigames by name.

const ROOT := "res://minigames"

static var _cache: Dictionary = {}
static var _scanned: bool = false


static func scan(force: bool = false) -> Dictionary:
	if _scanned and not force:
		return _cache
	_cache.clear()
	var dir := DirAccess.open(ROOT)
	if dir == null:
		push_error("MinigameRegistry: cannot open %s" % ROOT)
		return _cache
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if dir.current_is_dir() and entry != "sdk":
			var folder := ROOT.path_join(entry)
			var manifest_path := folder.path_join("manifest.json")
			if FileAccess.file_exists(manifest_path):
				var data := TuningLoader.load_file(manifest_path)
				if not data.is_empty():
					var m := MinigameManifest.from_json(data, folder)
					_cache[m.id] = m
		entry = dir.get_next()
	dir.list_dir_end()
	_scanned = true
	return _cache


static func get_manifest(id: String) -> MinigameManifest:
	scan()
	return _cache.get(id, null)


static func ids() -> Array:
	scan()
	var out := _cache.keys()
	out.sort()
	return out
