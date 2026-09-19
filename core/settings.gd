extends Node
## Per-user preferences (not balance): sensitivity, volumes, name, network defaults. Autoload
## `Settings`. Defaults come from tuning/controls.json; edits persist to user://settings.json.

signal changed

const PATH := "user://settings.json"

var player_name: String = ""
var mouse_sensitivity: float = 0.0022
var ads_sensitivity_multiplier: float = 0.6
var invert_y: bool = false
var volume_master: float = 1.0
var volume_music: float = 0.8
var volume_sfx: float = 1.0
var volume_ui: float = 0.9
var noray_host: String = "tomfol.io:8890"
var conditioner_profile: String = "lan"
var render_scale: float = 1.5   # 3D render scale; above 1 supersamples (cleaner ink lines), 1 for weak GPUs


func _ready() -> void:
	var defaults := Tuning.table("controls")
	mouse_sensitivity = float(defaults.get("mouse_sensitivity", mouse_sensitivity))
	ads_sensitivity_multiplier = float(defaults.get("ads_sensitivity_multiplier", ads_sensitivity_multiplier))
	invert_y = bool(defaults.get("invert_y", invert_y))
	load_file()


func load_file() -> void:
	if not FileAccess.file_exists(PATH):
		return
	var text := FileAccess.get_file_as_string(PATH)
	var data: Variant = JSON.parse_string(text)
	if not (data is Dictionary):
		Log.warn("settings", "Ignoring unreadable %s" % PATH)
		return
	var d: Dictionary = data
	player_name = str(d.get("player_name", player_name))
	mouse_sensitivity = float(d.get("mouse_sensitivity", mouse_sensitivity))
	ads_sensitivity_multiplier = float(d.get("ads_sensitivity_multiplier", ads_sensitivity_multiplier))
	invert_y = bool(d.get("invert_y", invert_y))
	volume_master = float(d.get("volume_master", volume_master))
	volume_music = float(d.get("volume_music", volume_music))
	volume_sfx = float(d.get("volume_sfx", volume_sfx))
	volume_ui = float(d.get("volume_ui", volume_ui))
	noray_host = str(d.get("noray_host", noray_host))
	conditioner_profile = str(d.get("conditioner_profile", conditioner_profile))
	render_scale = clampf(float(d.get("render_scale", render_scale)), 0.5, 2.0)
	Log.info("settings", "Loaded %s" % PATH)


func to_dict() -> Dictionary:
	return {
		"player_name": player_name, "mouse_sensitivity": mouse_sensitivity,
		"ads_sensitivity_multiplier": ads_sensitivity_multiplier, "invert_y": invert_y,
		"volume_master": volume_master, "volume_music": volume_music, "volume_sfx": volume_sfx,
		"volume_ui": volume_ui, "noray_host": noray_host, "conditioner_profile": conditioner_profile,
		"render_scale": render_scale,
	}


func save() -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f == null:
		Log.warn("settings", "Could not write %s" % PATH)
		return
	f.store_string(JSON.stringify(to_dict(), "  "))
	f.close()
	changed.emit()


## Set one field, apply it live and persist.
func set_value(key: String, value: Variant) -> void:
	if not (key in self):
		return
	set(key, value)
	save()
