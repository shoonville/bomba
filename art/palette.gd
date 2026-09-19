class_name Palette
extends RefCounted
## Colour lookups from tuning/palette.json. STYLE.md §1: fields, counters and accents behave
## differently; player identity colours are one global accent set under the value ceiling.


static func _hsv(arr: Array) -> Color:
	if arr.size() < 3:
		return Color.MAGENTA
	return Color.from_hsv(float(arr[0]) / 360.0, float(arr[1]), float(arr[2]))


static func player_colour(index: int) -> Color:
	var players: Array = Tuning.value("palette.players", [])
	if players.is_empty():
		return Color.WHITE
	var entry: Dictionary = players[posmod(index, players.size())]
	return _hsv(entry.get("hsv", [0, 0, 0.8]))


static func player_name(index: int) -> String:
	var players: Array = Tuning.value("palette.players", [])
	if players.is_empty():
		return "PLAYER"
	return str(players[posmod(index, players.size())].get("name", "PLAYER"))


static func map_colour(map_id: String, key: String) -> Color:
	var arr: Variant = Tuning.value("palette.maps.%s.%s" % [map_id, key], null)
	if arr == null:
		return Color.MAGENTA
	if key == "shadow_tint":
		return Color(float(arr[0]), float(arr[1]), float(arr[2]))
	return _hsv(arr)


static func hud_colour(key: String) -> Color:
	var arr: Variant = Tuning.value("palette.hud.%s" % key, null)
	if arr == null:
		return Color.WHITE
	return _hsv(arr)


static func value_ceiling() -> float:
	return Tuning.float_value("palette.value_ceiling", 0.85)


## Clamp any colour under the value ceiling without changing its hue.
static func under_ceiling(c: Color) -> Color:
	var ceiling := value_ceiling()
	if c.v > ceiling:
		return Color.from_hsv(c.h, c.s, ceiling, c.a)
	return c
