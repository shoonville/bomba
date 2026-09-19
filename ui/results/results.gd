extends Control
## Results screen: ranked list on the swirl, one accent, a button back to the lobby.

var _result: MinigameResult
var _list: VBoxContainer
var _podium_figures: Array = []
var _podium_t: float = 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	add_child(UiStyle.swirl_background("counter", "field"))
	var title := UiStyle.title("RESULTS", 96)
	title.position = Vector2(64, 40)
	add_child(title)
	UiStyle.slam(title)
	_list = VBoxContainer.new()
	_list.position = Vector2(90, 220)
	_list.add_theme_constant_override("separation", 10)
	add_child(_list)
	var btn := UiStyle.button("BACK TO LOBBY", func():
		Game.transition(func():
			queue_free()
			Game.show_menu()
		)
	, 26)
	btn.position = Vector2(90, 760)
	add_child(btn)


## The top three as figures on podium blocks, rendered in a SubViewport on the right: the winner
## bounces, the others stand. Colours come from the session registry.
func _build_podium(result: MinigameResult) -> void:
	var container := SubViewportContainer.new()
	container.position = Vector2(820, 150)
	container.size = Vector2(700, 560)
	container.stretch = true
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(container)
	var vp := SubViewport.new()
	vp.size = Vector2i(700, 560)
	vp.transparent_bg = true
	vp.msaa_3d = Viewport.MSAA_2X
	container.add_child(vp)
	var world := Node3D.new()
	vp.add_child(world)
	var cam := Camera3D.new()
	cam.position = Vector3(0.0, 2.2, 6.4)
	cam.fov = 40.0
	world.add_child(cam)
	cam.look_at(Vector3(0.0, 1.2, 0.0), Vector3.UP)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, 30.0, 0.0)
	sun.light_energy = 1.1
	world.add_child(sun)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0, 0, 0, 0)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = UiStyle.paper()
	e.ambient_light_energy = 0.5
	e.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.environment = e
	world.add_child(env)
	var shadow := Palette.map_colour("board", "shadow_tint")
	var block_mat := CelMaterial.for_colour(UiStyle.ink().lightened(0.25), shadow)
	var slots := [[0.0, 1.0], [-1.7, 0.65], [1.7, 0.4]]   # x, block height for #1, #2, #3
	for i in mini(3, result.rankings.size()):
		var r: Dictionary = result.rankings[i]
		var block := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(1.4, float(slots[i][1]), 1.4)
		block.mesh = bm
		block.position = Vector3(float(slots[i][0]), float(slots[i][1]) * 0.5, 0.0)
		block.material_override = block_mat
		world.add_child(block)
		var rank := Label3D.new()
		rank.text = "%d" % int(r["rank"])
		rank.font_size = 96
		rank.pixel_size = 0.006
		rank.outline_size = 16
		rank.modulate = Palette.hud_colour("score") if i == 0 else UiStyle.paper()
		rank.outline_modulate = UiStyle.ink()
		rank.position = block.position + Vector3(0.0, 0.0, 0.71)
		world.add_child(rank)
		var colour_index := 0
		var peer := int(r["peer_id"])
		if Session.players.has(peer):
			colour_index = int(Session.players[peer].colour_index)
		var f := Figure.new()
		world.add_child(f)
		f.build(Palette.player_colour(colour_index), "board", 1.62, false)
		f.position = Vector3(float(slots[i][0]), float(slots[i][1]), 0.0)
		f.rotation.y = PI   # face the camera
		_podium_figures.append(f)


func _process(delta: float) -> void:
	_podium_t += delta
	for i in _podium_figures.size():
		var f := _podium_figures[i] as Figure
		if f == null:
			continue
		# The winner hops on the spot; the others stand and breathe.
		var hop := i == 0 and fmod(_podium_t, 1.4) < 0.45
		var lift := sin(fmod(_podium_t, 1.4) / 0.45 * PI) * 0.35 if hop else 0.0
		f.position.y = f.position.y * 0.0 + (1.0 if i == 0 else (0.65 if i == 1 else 0.4)) + lift
		f.animate(0.0, not hop, 0.0, true, delta)


func show_result(result: MinigameResult) -> void:
	_result = result
	_build_podium(result)
	var i := 0
	for r in result.rankings:
		var first := int(r["rank"]) == 1
		var value := str(r["label"]) if r.has("label") else "%d" % int(r["score"])
		var l := UiStyle.label("#%d   %s   %s" % [int(r["rank"]), str(r["display_name"]).to_upper(), value],
			44 if first else 30, Palette.hud_colour("score") if first else UiStyle.paper())
		_list.add_child(l)
		UiStyle.slam(l, 0.12 + 0.08 * i)
		i += 1
