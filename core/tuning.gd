extends Node
## Every gameplay value lives in tuning/*.json and is read through here. Autoload `Tuning`.
## F5 (`tuning_reload`) reloads at runtime in debug builds; listeners refresh on `reloaded`.

signal reloaded

const DIR := "res://tuning"

var _tables: Dictionary = {}


func _ready() -> void:
	load_all()


func load_all() -> void:
	_tables = TuningLoader.load_dir(DIR)
	var names := _tables.keys()
	names.sort()
	Log.info("tuning", "Loaded %d tables: %s" % [_tables.size(), ", ".join(names)])


func table(name: String) -> Dictionary:
	if not _tables.has(name):
		Log.error("tuning", "Missing tuning table '%s'" % name)
		return {}
	return _tables[name]


## Dotted lookup, e.g. value("weapons.sniper.scope_in_ticks"). Errors loudly when missing and
## no default was given; a silent default hides a broken feature.
func value(path: String, default: Variant = null) -> Variant:
	var v: Variant = TuningLoader.lookup(_tables, path, null)
	if v == null:
		if default == null:
			Log.error("tuning", "Missing tuning value '%s'" % path)
		return default
	return v


func int_value(path: String, default: int = 0) -> int:
	return int(value(path, default))


func float_value(path: String, default: float = 0.0) -> float:
	return float(value(path, default))


func reload() -> void:
	load_all()
	reloaded.emit()
	Log.info("tuning", "Reloaded")


func _unhandled_input(event: InputEvent) -> void:
	if OS.is_debug_build() and event.is_action_pressed("tuning_reload"):
		reload()
