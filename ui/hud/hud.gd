extends Control
## The in-game HUD (STYLE.md §5): shaped, edge-anchored, never boxed, never more than four
## things at once. Health swash bottom-left, kills + timer top-right, ammo bottom-right,
## crosshair / hitmarker / scope in the centre, a short kill feed top-left that fades.

var _player: Player
var _arena: Node
var _last_count: int = -1
var _hit_flash: float = 0.0
var _hit_kind: int = 0
var _damage_flash: float = 0.0
var _feed: Array = []
var _font: Font
var _score_col: Color
var _meter_col: Color
var _danger_col: Color
var _ink: Color
var _paper: Color


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = ThemeDB.fallback_font
	_score_col = Palette.hud_colour("score")
	_meter_col = Palette.hud_colour("meter")
	_danger_col = Palette.hud_colour("danger")
	_ink = Palette.hud_colour("ink")
	_paper = Palette.hud_colour("paper")
	Events.local_hit_predicted.connect(_on_hit)
	Events.local_damaged.connect(_on_damaged)
	Events.kill.connect(_on_kill)


func _on_hit(kind: int, _victim: int) -> void:
	_hit_flash = 1.0
	_hit_kind = kind


func _on_damaged(_amount: int, _from: int) -> void:
	_damage_flash = 1.0


func _on_kill(killer_id: int, victim_id: int, weapon: String, headshot: bool, _tick: int) -> void:
	var kn := _name_of(killer_id)
	var vn := _name_of(victim_id)
	_feed.append({"text": "%s  ▸  %s   %s%s" % [kn, vn, weapon.to_upper(), "  HEADSHOT" if headshot else ""], "life": 4.0,
		"mine": killer_id == multiplayer.get_unique_id()})
	while _feed.size() > 4:
		_feed.pop_front()


func _name_of(id: int) -> String:
	if _arena != null and _arena.has_method("get_player"):
		var p = _arena.get_player(id)
		if p != null:
			return p.display_name
	return "world" if id == 0 else "#%d" % id


func _process(delta: float) -> void:
	_arena = Game.active_minigame
	if _arena != null and _arena.has_method("get_local_player"):
		_player = _arena.get_local_player()
	if _arena != null and _arena.has_method("warmup_seconds_left"):
		# One tick per countdown digit; the round-start sting covers the zero.
		var left := ceili(float(_arena.warmup_seconds_left()))
		if left != _last_count:
			if left > 0 and _last_count > 0:
				Audio.play("ui_click", -4.0, 1.0 if left > 1 else 1.25, "UI")
			_last_count = left
	_hit_flash = maxf(0.0, _hit_flash - delta * 5.0)
	_damage_flash = maxf(0.0, _damage_flash - delta * 2.5)
	for f in _feed:
		f["life"] -= delta
	_feed = _feed.filter(func(f): return f["life"] > 0.0)
	queue_redraw()


func _draw() -> void:
	var size := get_rect().size
	if _player == null or not is_instance_valid(_player):
		return
	var tick := NetworkTime.tick
	var scoped := _player.weapons.is_scoped(tick)
	var progress := _player.weapons.ads_progress(tick)
	var def := _player.weapons.current_def()
	var spectating := _arena != null and _arena.has_method("spectating_name") and str(_arena.spectating_name()) != ""
	if spectating:
		# Eliminated and watching someone else: only the round state stays on screen.
		_draw_score(size)
		_draw_feed()
	else:
		if def != null and def.is_sniper() and progress > 0.9:
			_draw_scope(size, scoped)
		else:
			_draw_crosshair(size, progress)
		_draw_hitmarker(size)
		_draw_health(size)
		_draw_score(size)
		_draw_ammo(size, def)
		_draw_feed()
	if _damage_flash > 0.0:
		_draw_damage(size)
	if _arena != null and _arena.has_method("in_warmup") and _arena.in_warmup():
		var name := "GET READY"
		if "manifest" in _arena and _arena.manifest != null:
			name = "%s  ·  GET READY" % _arena.manifest.display_name
		_draw_centre_text(size, name, 56, _score_col)
		if _arena.has_method("warmup_seconds_left"):
			var left := ceili(float(_arena.warmup_seconds_left()))
			if left > 0:
				var digit := "%d" % left
				var dw := _font.get_string_size(digit, HORIZONTAL_ALIGNMENT_CENTER, -1, 120).x
				_draw_outlined(Vector2((size.x - dw) * 0.5, size.y * 0.3 + 120.0), digit, 120, _score_col, 10.0, -0.22)
	if _player.health <= 0:
		var txt := "DOWN"
		if _arena != null and _arena.has_method("centre_text") and str(_arena.centre_text()) != "":
			txt = str(_arena.centre_text())
		_draw_centre_text(size, txt, 64 if not spectating else 40, _danger_col)
		if spectating:
			var hint := "CLICK TO SWITCH"
			var hw := _font.get_string_size(hint, HORIZONTAL_ALIGNMENT_CENTER, -1, 20).x
			_draw_outlined(Vector2((size.x - hw) * 0.5, size.y * 0.3 + 34.0), hint, 20, _paper)


func _draw_crosshair(size: Vector2, progress: float) -> void:
	var c := size * 0.5
	var gap := lerpf(9.0, 4.0, progress)
	var len := 9.0
	var w := 3.0
	for dir in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
		var a: Vector2 = c + dir * gap
		var b: Vector2 = c + dir * (gap + len)
		draw_line(a, b, _ink, w + 2.5)
		draw_line(a, b, _paper, w)


func _draw_scope(size: Vector2, settled: bool) -> void:
	var c := size * 0.5
	var r := size.y * 0.42
	# Flat ink everywhere except the lens: four bands around the lens' bounding square plus four
	# corner fans (square corner + quarter arc). Godot cannot subtract shapes, so build the ring.
	var sq := Rect2(c.x - r, c.y - r, 2.0 * r, 2.0 * r)
	draw_rect(Rect2(0.0, 0.0, size.x, maxf(0.0, sq.position.y)), _ink)
	draw_rect(Rect2(0.0, sq.end.y, size.x, maxf(0.0, size.y - sq.end.y)), _ink)
	draw_rect(Rect2(0.0, sq.position.y, maxf(0.0, sq.position.x), sq.size.y), _ink)
	draw_rect(Rect2(sq.end.x, sq.position.y, maxf(0.0, size.x - sq.end.x), sq.size.y), _ink)
	var corners := [Vector2(sq.position.x, sq.position.y), Vector2(sq.end.x, sq.position.y),
		Vector2(sq.end.x, sq.end.y), Vector2(sq.position.x, sq.end.y)]
	for k in 4:
		var a0 := PI + float(k) * PI * 0.5
		var pts := PackedVector2Array([corners[k]])
		for i in 17:
			var a := a0 + float(i) / 16.0 * PI * 0.5
			pts.append(c + Vector2(cos(a), sin(a)) * r)
		draw_colored_polygon(pts, _ink)
	draw_arc(c, r, 0.0, TAU, 96, _ink, 10.0)
	draw_arc(c, r - 8.0, 0.0, TAU, 96, _paper, 3.0)
	var reticle := _meter_col if settled else _danger_col
	for seg in [[Vector2(-r, 0), Vector2(-14, 0)], [Vector2(14, 0), Vector2(r, 0)], [Vector2(0, -r), Vector2(0, -14)], [Vector2(0, 14), Vector2(0, r)]]:
		draw_line(c + seg[0], c + seg[1], _ink, 5.0)
		draw_line(c + seg[0], c + seg[1], reticle, 2.0)
	draw_circle(c, 3.0, reticle)


func _draw_hitmarker(size: Vector2) -> void:
	if _hit_flash <= 0.0:
		return
	var c := size * 0.5
	var col := _danger_col if _hit_kind == HitscanResolver.HEAD else _paper
	col.a = _hit_flash
	var ink := _ink
	ink.a = _hit_flash
	var s := 14.0 + (1.0 - _hit_flash) * 6.0
	for d in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		var a: Vector2 = c + d * 6.0
		var b: Vector2 = c + d * s
		draw_line(a, b, ink, 6.0)
		draw_line(a, b, col, 3.0)


func _draw_health(size: Vector2) -> void:
	# A tapered swash along the bottom-left edge: thick at the corner, tapering as it sweeps up.
	var frac := clampf(float(_player.health) / float(_player.max_health), 0.0, 1.0)
	var origin := Vector2(28.0, size.y - 28.0)
	var length := 300.0
	var pts_outline := PackedVector2Array()
	var pts_fill := PackedVector2Array()
	var steps := 24
	var top := PackedVector2Array()
	var bottom := PackedVector2Array()
	for i in steps + 1:
		var t := float(i) / float(steps)
		var x := origin.x + t * length
		var lift := -t * t * 70.0
		var thickness := lerpf(34.0, 10.0, t)
		top.append(Vector2(x, origin.y + lift - thickness))
		bottom.append(Vector2(x, origin.y + lift))
	for p in top:
		pts_outline.append(p)
	for i in range(bottom.size() - 1, -1, -1):
		pts_outline.append(bottom[i])
	draw_colored_polygon(pts_outline, _ink)
	var fill_steps := int(round(frac * steps))
	if fill_steps >= 1:
		for i in fill_steps + 1:
			pts_fill.append(top[i] + Vector2(0, 4))
		for i in range(fill_steps, -1, -1):
			pts_fill.append(bottom[i] - Vector2(0, 4))
		var col := _meter_col if frac > 0.35 else _danger_col
		draw_colored_polygon(pts_fill, col)
	var protected := NetworkTime.tick < _player.protected_until_tick
	var label := "%d" % maxi(0, _player.health)
	_draw_outlined(Vector2(origin.x + 6, origin.y - 44), label, 30, _paper)
	if protected:
		_draw_outlined(Vector2(origin.x + 70, origin.y - 44), "SHIELDED", 18, _score_col)


func _draw_score(size: Vector2) -> void:
	var kills := "%d" % _player.kills
	var pos := Vector2(size.x - 40.0 - _font.get_string_size(kills, HORIZONTAL_ALIGNMENT_RIGHT, -1, 84).x, 96.0)
	_draw_outlined(pos, kills, 84, _score_col, 8.0, -0.24)
	var remaining := 0.0
	if _arena != null and _arena.has_method("time_remaining_seconds"):
		remaining = _arena.time_remaining_seconds()
	var mins := int(remaining) / 60
	var secs := int(remaining) % 60
	var timer := "%d:%02d" % [mins, secs]
	var tw := _font.get_string_size(timer, HORIZONTAL_ALIGNMENT_RIGHT, -1, 26).x
	_draw_outlined(Vector2(size.x - 40.0 - tw, 128.0), timer, 26, _paper)
	var deaths := "%d DOWN" % _player.deaths
	var dw := _font.get_string_size(deaths, HORIZONTAL_ALIGNMENT_RIGHT, -1, 18).x
	_draw_outlined(Vector2(size.x - 40.0 - dw, 152.0), deaths, 18, _paper)


func _draw_ammo(size: Vector2, def: WeaponDef) -> void:
	if def == null:
		return
	var slot := _player.weapons.slot
	var ammo := _player.weapons.ammo_for_slot(slot)
	var origin := Vector2(size.x - 40.0, size.y - 34.0)
	# Angled ticks, one per round, right-aligned, tapering
	var n := def.magazine
	var w := 8.0 if n <= 12 else 4.0
	var gap := 4.0 if n <= 12 else 2.0
	for i in n:
		var x := origin.x - (n - i) * (w + gap)
		var h := 18.0 + i * (10.0 / float(maxi(n - 1, 1)))
		var poly := PackedVector2Array([Vector2(x, origin.y), Vector2(x + w, origin.y), Vector2(x + w + 5, origin.y - h), Vector2(x + 5, origin.y - h)])
		draw_colored_polygon(poly, _ink)
		if i < ammo:
			var inner := PackedVector2Array([Vector2(x + 1.5, origin.y - 1.5), Vector2(x + w - 1.5, origin.y - 1.5), Vector2(x + w + 3.5, origin.y - h + 2), Vector2(x + 3.5, origin.y - h + 2)])
			draw_colored_polygon(inner, _score_col)
	var name := def.display_name
	if _player.weapons.is_reloading():
		name = "RELOADING"
	elif NetworkTime.tick < _player.weapons.swap_until_tick:
		name = "..."
	var nw := _font.get_string_size(name, HORIZONTAL_ALIGNMENT_RIGHT, -1, 22).x
	_draw_outlined(Vector2(origin.x - nw, origin.y - 40.0), name, 22, _paper)


func _draw_feed() -> void:
	var y := 40.0
	for f in _feed:
		var col := _score_col if f["mine"] else _paper
		col.a = clampf(float(f["life"]), 0.0, 1.0)
		_draw_outlined(Vector2(28.0, y), str(f["text"]), 20, col)
		y += 26.0


func _draw_damage(size: Vector2) -> void:
	var col := _danger_col
	col.a = _damage_flash * 0.35
	var t := 26.0 * _damage_flash + 8.0
	draw_rect(Rect2(0, 0, size.x, t), col)
	draw_rect(Rect2(0, size.y - t, size.x, t), col)
	draw_rect(Rect2(0, 0, t, size.y), col)
	draw_rect(Rect2(size.x - t, 0, t, size.y), col)


func _draw_centre_text(size: Vector2, text: String, font_size: int, col: Color) -> void:
	var w := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size).x
	_draw_outlined(Vector2((size.x - w) * 0.5, size.y * 0.3), text, font_size, col, 6.0)


## Heavy italic outlined type (STYLE.md §5 and the grind-shot HUD): a shear stands in for a real
## display face until one is chosen.
func _draw_outlined(pos: Vector2, text: String, font_size: int, col: Color, outline: float = 4.0, shear: float = -0.18) -> void:
	var ink := _ink
	ink.a = col.a
	draw_set_transform_matrix(Transform2D(Vector2(1.0, 0.0), Vector2(shear, 1.0), pos))
	draw_string_outline(_font, Vector2.ZERO, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, int(outline), ink)
	draw_string(_font, Vector2.ZERO, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, col)
	draw_set_transform_matrix(Transform2D())
