class_name Briefing
extends Control
## The screen before a minigame (Sean, 2026-09-22): its name, what wins, how it plays, the
## controls, a live look at the map (the built match seen from its showcase vantage, orbiting,
## in a viewport: drawn, like everything else, no video file), and the seats with their READY
## state. READY (or Space) readies you; the host can FORCE START. The match holds everyone
## frozen until then; the round RPC ends the briefing everywhere and this leaves with a wipe.
## In the menu's language (UiStyle) on the marbled swirl.

var _match: Node
var _cards: Dictionary = {}     # peer_id -> the READY tag label
var _ready_button: Button
var _force_button: Button
var _preview: SubViewport
var _preview_cam: Camera3D
var _orbit_centre: Vector3 = Vector3(1.0, 2.5, -2.0)
var _orbit_radius: float = 26.0
var _orbit_height: float = 11.0
var _orbit_t: float = 0.0
var _leaving: bool = false


func setup(match_node: Node) -> void:
	_match = match_node
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := UiStyle.swirl_background()
	add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var manifest = _match.manifest
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 60)
	margin.add_theme_constant_override("margin_right", 60)
	margin.add_theme_constant_override("margin_top", 28)
	margin.add_theme_constant_override("margin_bottom", 28)
	add_child(margin)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	margin.add_child(col)

	# Title and what wins.
	var title := UiStyle.title(str(manifest.display_name) if manifest != null else "MINIGAME", 84)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)
	UiStyle.slam(title)
	if manifest != null and str(manifest.tagline) != "":
		var tag := UiStyle.label(str(manifest.tagline), 26, UiStyle.accent())
		tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(tag)

	# The map in a viewport on the left, the rules and controls on the right.
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 40)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(row)
	row.add_child(_build_preview())
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override("separation", 6)
	row.add_child(text)
	text.add_child(UiStyle.label("HOW IT PLAYS", 24, UiStyle.accent()))
	var desc := UiStyle.label(str(manifest.description) if manifest != null else "", 22)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(0, 0)
	desc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_child(desc)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 10)
	text.add_child(spacer)
	text.add_child(UiStyle.label("CONTROLS", 24, UiStyle.accent()))
	if manifest != null:
		for c in manifest.controls:
			var line := UiStyle.label(str(c), 20)
			line.custom_minimum_size = Vector2(0, 30)
			text.add_child(line)

	# The seats and their READY state, then the buttons.
	var seats := HBoxContainer.new()
	seats.add_theme_constant_override("separation", 14)
	seats.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(seats)
	for p in _match.players:
		var mp := p as MinigamePlayer
		var card := PanelContainer.new()
		card.add_theme_stylebox_override("panel", UiStyle.skewed_box(Color(UiStyle.ink(), 0.8), mp.colour, 0.2, 8))
		var inner := VBoxContainer.new()
		inner.add_theme_constant_override("separation", 0)
		card.add_child(inner)
		var name := UiStyle.label(mp.display_name.to_upper(), 20, mp.colour)
		name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name.custom_minimum_size = Vector2(170, 30)
		inner.add_child(name)
		var tag := UiStyle.label("BOT" if mp.is_bot else "NOT READY", 16)
		tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tag.custom_minimum_size = Vector2(0, 24)
		inner.add_child(tag)
		seats.add_child(card)
		_cards[mp.peer_id] = tag
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 24)
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(buttons)
	_ready_button = UiStyle.button("READY", _toggle_ready, 28)
	_ready_button.custom_minimum_size = Vector2(260, 52)
	buttons.add_child(_ready_button)
	if _match.is_authority():
		_force_button = UiStyle.button("FORCE START", func(): _match.force_start(), 28, Palette.hud_colour("score"))
		_force_button.custom_minimum_size = Vector2(260, 52)
		buttons.add_child(_force_button)
	var hint := UiStyle.label("SPACE  ready   ·   the round starts when everyone is ready" + ("   ·   or when the host forces it" if not _match.is_authority() else ""), 16)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(hint)
	Events.round_started.connect(_on_round_started)
	Events.minigame_finished.connect(func(_r): _leave_now())


## The built match seen from its showcase vantage, orbiting slowly, in its own viewport that
## shares the world: the live "video" of the map.
func _build_preview() -> Control:
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", UiStyle.skewed_box(UiStyle.ink(), UiStyle.paper(), 0.0, 6))
	frame.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	frame.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var holder := SubViewportContainer.new()
	holder.stretch = true
	holder.custom_minimum_size = Vector2(720, 405)
	holder.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	holder.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	frame.add_child(holder)
	_preview = SubViewport.new()
	_preview.size = Vector2i(720, 405)
	_preview.world_3d = get_viewport().world_3d if is_inside_tree() else null
	_preview.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_preview.msaa_3d = Viewport.MSAA_2X
	holder.add_child(_preview)
	var show: Dictionary = _match.layout.get("showcase", {}) if "layout" in _match else {}
	var pos: Vector3 = show.get("pos", Vector3(-14.0, 11.0, 24.0))
	_orbit_centre = show.get("look", Vector3(1.0, 2.5, -2.0))
	var flat := Vector2(pos.x - _orbit_centre.x, pos.z - _orbit_centre.z)
	_orbit_radius = maxf(flat.length(), 8.0)
	_orbit_height = pos.y
	_orbit_t = flat.angle()
	_preview_cam = Camera3D.new()
	_preview_cam.fov = 55.0
	_preview_cam.far = 400.0
	_preview.add_child(_preview_cam)
	_preview_cam.current = true
	var post := PostStack.new()
	_preview_cam.add_child(post)
	post.setup("arena")
	_place_preview_cam()
	return frame


func _place_preview_cam() -> void:
	if _preview_cam == null:
		return
	var p := _orbit_centre + Vector3(cos(_orbit_t) * _orbit_radius, 0.0, sin(_orbit_t) * _orbit_radius)
	p.y = _orbit_height
	_preview_cam.global_position = p
	_preview_cam.look_at(_orbit_centre, Vector3.UP)


func _ready() -> void:
	if _preview != null and _preview.world_3d == null:
		_preview.world_3d = get_viewport().world_3d


func _process(delta: float) -> void:
	_orbit_t += delta * 0.12
	_place_preview_cam()
	if _match == null or not is_instance_valid(_match):
		return
	for peer_id in _cards:
		var tag: Label = _cards[peer_id]
		var mp: MinigamePlayer = null
		for p in _match.players:
			if (p as MinigamePlayer).peer_id == peer_id:
				mp = p
		if mp != null and not mp.is_bot:
			var ready: bool = _match.is_ready(peer_id)
			tag.text = "READY" if ready else "NOT READY"
			tag.add_theme_color_override("font_color", Palette.hud_colour("score") if ready else UiStyle.paper())
	if _ready_button != null:
		_ready_button.text = "NOT READY" if _match.local_ready() else "READY"


func _unhandled_input(event: InputEvent) -> void:
	if _leaving or _match == null:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var key := (event as InputEventKey).keycode
		if key == KEY_SPACE or key == KEY_ENTER or key == KEY_KP_ENTER:
			_toggle_ready()
			get_viewport().set_input_as_handled()


func _toggle_ready() -> void:
	if _match != null and is_instance_valid(_match):
		_match.set_local_ready(not _match.local_ready())


## The round is on: leave under a wipe, the mouse captured for the match.
func _on_round_started(_end_tick: int) -> void:
	if _leaving:
		return
	_leaving = true
	set_process(false)
	Game.transition(func():
		if not Game.args.has("screenshot"):
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		queue_free()
	)


func _leave_now() -> void:
	if not _leaving:
		_leaving = true
		queue_free()
