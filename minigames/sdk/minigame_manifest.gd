class_name MinigameManifest
extends RefCounted
## What a minigame declares about itself (minigames/<id>/manifest.json).

var id: String = ""
var display_name: String = ""
var tagline: String = ""   # one line under GET READY: what wins here
var min_players: int = 2
var max_players: int = 6
var camera: String = "first_person"  # or "third_person"
var scoring: String = "kills"
var time_limit_seconds: int = 0
var weapons: PackedStringArray = []
var bot_profile: String = "fps"
var scene_path: String = ""
var description: String = ""             # the briefing: how it plays, a few lines
var controls: PackedStringArray = []     # the briefing: "KEY  what it does", one per line


static func from_json(d: Dictionary, folder: String) -> MinigameManifest:
	var m := MinigameManifest.new()
	m.id = str(d.get("id", folder.get_file()))
	m.display_name = str(d.get("display_name", m.id.to_upper()))
	m.tagline = str(d.get("tagline", ""))
	m.min_players = int(d.get("min_players", 2))
	m.max_players = int(d.get("max_players", 6))
	m.camera = str(d.get("camera", "first_person"))
	m.scoring = str(d.get("scoring", "kills"))
	m.time_limit_seconds = int(d.get("time_limit_seconds", 0))
	for w in d.get("weapons", []):
		m.weapons.append(str(w))
	m.bot_profile = str(d.get("bot_profile", "fps"))
	m.scene_path = folder.path_join(str(d.get("scene", "minigame.tscn")))
	m.description = str(d.get("description", ""))
	for c in d.get("controls", []):
		m.controls.append(str(c))
	return m
