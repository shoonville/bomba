class_name PipelineWarmup
extends Node3D
## Draws one of every material kind the game uses for a few frames at boot, behind a cover in the
## boot clear colour, so the shader variant groups, GPU pipelines and the shadow atlas exist before
## the first match instead of being created on its first frame. Measured on Sean's desktop (RTX
## 5090, Godot 4.7.2): a minigame's first frame stalled 313–381 ms and a board → minigame switch
## 292 ms, the same whether that frame allocated 635 MB or 247 MB, so the cost is first-use
## pipeline creation, not memory. `--no_warmup` skips it (for A/B runs).

const FRAMES := 3


## Cover the screen, render FRAMES frames of the warm-up scene, then free everything.
func run(cover_parent: Node) -> void:
	var t0 := Time.get_ticks_msec()
	var cover := ColorRect.new()
	cover.name = "WarmupCover"
	cover.color = ProjectSettings.get_setting("rendering/environment/defaults/default_clear_color", Color(0.72, 0.62, 0.48))
	cover.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cover_parent.add_child(cover)
	_build()
	for i in FRAMES:
		await RenderingServer.frame_post_draw
	cover.queue_free()
	queue_free()
	Log.info("perf", "Pipeline warm-up: %d ms over %d frames" % [Time.get_ticks_msec() - t0, FRAMES])


func _build() -> void:
	var map_id := "arena"
	var shadow := Palette.map_colour(map_id, "shadow_tint")
	# Sky, ambient and sun as a match builds them (fps_match.gd, board_view.gd): the cloud sky
	# shader, hard orthogonal directional shadows (this allocates the 8192 atlas).
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = load("res://art/shaders/sky_clouds.gdshader")
	sky_mat.set_shader_parameter("sky_top", Palette.map_colour(map_id, "sky_top"))
	sky_mat.set_shader_parameter("sky_horizon", Palette.map_colour(map_id, "sky_bottom"))
	sky_mat.set_shader_parameter("cloud_lit", Palette.map_colour(map_id, "cloud_lit"))
	sky_mat.set_shader_parameter("cloud_shadow", Palette.map_colour(map_id, "cloud_shadow"))
	sky_mat.set_shader_parameter("ink", Palette.map_colour(map_id, "line"))
	sky_mat.set_shader_parameter("cloud_coverage", 0.44)
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_32
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Palette.map_colour(map_id, "counter")
	env.ambient_light_energy = 0.5
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 90.0
	sun.light_angular_distance = 0.0
	sun.shadow_bias = 0.03
	sun.rotation_degrees = Vector3(-52.0, 35.0, 0.0)
	add_child(sun)
	var cam := Camera3D.new()
	cam.position = Vector3(0.0, 1.6, 4.0)
	add_child(cam)
	cam.current = true
	var post := PostStack.new()
	cam.add_child(post)
	post.setup(map_id)

	# Cel: opaque, emissive and the viewmodel variant, on a floor so the shadow pass draws too.
	var floor := PlaneMesh.new()
	floor.size = Vector2(12.0, 12.0)
	_mesh(floor, Vector3.ZERO, CelMaterial.for_tone(map_id, "floor"))
	_mesh(BoxMesh.new(), Vector3(-1.5, 0.5, 0.0), CelMaterial.for_colour(Color(0.8, 0.4, 0.3), shadow))
	_mesh(BoxMesh.new(), Vector3(0.0, 0.5, 0.0), CelMaterial.for_colour(Color(0.9, 0.8, 0.2), shadow, 1.2))
	_mesh(BoxMesh.new(), Vector3(1.5, 0.5, 0.0), CelMaterial.for_colour(Color(0.9, 0.85, 0.7), shadow, 0.0, true))
	var sphere := SphereMesh.new()
	sphere.radius = 0.3
	sphere.height = 0.6
	_mesh(sphere, Vector3(0.0, 1.4, 0.0), CelMaterial.for_colour(Color(0.3, 0.6, 0.9), shadow, 0.5))

	# The sniper's lens glass, the AR's screen pane and red dot (viewmodel.gd).
	var lens := StandardMaterial3D.new()
	lens.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	lens.albedo_color = Color(0.55, 0.85, 1.0, 0.5)
	lens.metallic = 0.85
	lens.roughness = 0.12
	lens.metallic_specular = 0.9
	lens.emission_enabled = true
	lens.emission = Color(0.25, 0.6, 0.85)
	lens.emission_energy_multiplier = 0.35
	lens.cull_mode = BaseMaterial3D.CULL_DISABLED
	lens.no_depth_test = true
	_mesh(sphere, Vector3(-0.8, 1.4, 1.0), lens)
	var screen := StandardMaterial3D.new()
	screen.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	screen.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	screen.albedo_color = Color(0.4, 0.9, 0.9, 0.32)
	screen.cull_mode = BaseMaterial3D.CULL_DISABLED
	screen.no_depth_test = true
	screen.render_priority = 2
	_mesh(BoxMesh.new(), Vector3(0.8, 1.4, 1.0), screen)
	var dot := StandardMaterial3D.new()
	dot.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dot.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dot.albedo_color = Palette.hud_colour("danger")
	dot.no_depth_test = true
	dot.render_priority = 3
	_mesh(sphere, Vector3(0.8, 1.6, 1.2), dot)

	# The board's speech bubble (unshaded billboard quad).
	var bubble := StandardMaterial3D.new()
	bubble.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bubble.albedo_color = Palette.hud_colour("paper")
	bubble.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	var quad := QuadMesh.new()
	quad.size = Vector2(1.2, 0.6)
	_mesh(quad, Vector3(-1.5, 1.8, 0.0), bubble)

	# Name tags, die numbers, the "?" sign: alpha-cut Label3D (opaque pass, inked by the post).
	var label := Label3D.new()
	label.text = "BOMBA"
	label.font_size = 40
	label.pixel_size = 0.005
	label.outline_size = 12
	label.modulate = Palette.hud_colour("paper")
	label.outline_modulate = Palette.map_colour(map_id, "line")
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.alpha_cut = Label3D.ALPHA_CUT_DISCARD
	label.position = Vector3(0.0, 2.2, 0.0)
	add_child(label)

	# Shot feedback: a tracer, an impact burst (depth-tested) and a muzzle burst (not).
	Tracer.spawn(self, Vector3(-2.0, 1.0, 1.5), Vector3(2.0, 1.2, -1.0), Color(1.0, 0.9, 0.5), HitscanResolver.BODY, 2.0)
	Burst.spawn_muzzle(self, Vector3(0.6, 1.0, 2.0), Color(1.0, 0.8, 0.4))


func _mesh(mesh: Mesh, at: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = at
	mi.material_override = mat
	add_child(mi)
