class_name TuningLoader
extends RefCounted
## Plain loader for tuning/*.json. Used by the Tuning autoload and by headless tests.
##
## JSON numbers arrive as floats; typed config classes (MovementConfig, WeaponDef, ...) do the
## casting, so gameplay code never reads raw dictionaries.


static func load_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("Tuning file missing: %s" % path)
		return {}
	var text := FileAccess.get_file_as_string(path)
	var json := JSON.new()
	var err := json.parse(text)
	if err != OK:
		push_error("Tuning parse error in %s line %d: %s" % [path, json.get_error_line(), json.get_error_message()])
		return {}
	if not (json.data is Dictionary):
		push_error("Tuning file %s must hold an object at the top level" % path)
		return {}
	return json.data


static func load_dir(dir_path: String) -> Dictionary:
	var tables := {}
	var dir := DirAccess.open(dir_path)
	if dir == null:
		push_error("Tuning directory missing: %s" % dir_path)
		return tables
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if not dir.current_is_dir() and entry.ends_with(".json"):
			var name := entry.get_basename()
			tables[name] = load_file(dir_path.path_join(entry))
		entry = dir.get_next()
	dir.list_dir_end()
	return tables


## Resolve "table.key.subkey" inside a tables dictionary. Returns `default` when missing.
static func lookup(tables: Dictionary, path: String, default: Variant = null) -> Variant:
	var cur: Variant = tables
	for part in path.split("."):
		if cur is Dictionary and (cur as Dictionary).has(part):
			cur = cur[part]
		else:
			return default
	return cur
