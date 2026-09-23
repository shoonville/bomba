class_name Burst
extends RefCounted
## Drawn feedback bursts (STYLE.md §5, the BRC boost burst): a spiky star built as three billboard
## triangle fans — ink rim, colour body, white core. Scales in fast, fades out faster. No particles.
##
## Meshes and materials are built once and shared (2026-09-22): a burst used to build three new
## ArrayMeshes and three new StandardMaterial3Ds on every shot, and each new surface cost the
## renderer a pipeline compilation on the frame of the shot (on Sean's 5090 at 165 Hz the frame
## of a shot ran 19–20 ms against a 6 ms median: the "skipping frames" he felt). Now a burst is
## three MeshInstance3Ds over a unit star from a small seeded set, sized by the node's scale, and
## fades through GeometryInstance3D.transparency instead of a material of its own.

const VARIANTS := 4   # unit stars per (points, layer), so bursts do not all look alike

static var _meshes: Dictionary = {}      # "points|layer|variant" -> ArrayMesh, outer radius 1
static var _materials: Dictionary = {}   # "colour|priority|depth" -> StandardMaterial3D
static var _serial: int = 0


static func _star(points: int, r_outer: float, r_inner: float, seed_value: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var verts := PackedVector3Array()
	var rim := PackedVector3Array()
	var n := points * 2
	for i in n:
		var a := float(i) / float(n) * TAU
		var r := r_outer * rng.randf_range(0.7, 1.0) if i % 2 == 0 else r_inner * rng.randf_range(0.6, 1.0)
		rim.append(Vector3(cos(a) * r, sin(a) * r, 0.0))
	for i in n:
		verts.append(Vector3.ZERO)
		verts.append(rim[i])
		verts.append(rim[(i + 1) % n])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## A unit star for a layer (0 the ink rim, 1 the colour body, 2 the white core) from the seeded
## set. The rim and the body share a seed so the rim is the body's own outline, a size up.
static func _mesh_for(points: int, layer: int, variant: int) -> ArrayMesh:
	var key := "%d|%d|%d" % [points, layer, variant]
	if not _meshes.has(key):
		var radii: Array = [[1.18, 0.52], [1.0, 0.42], [0.48, 0.20]][layer]
		var seed_value := 7919 * points + 131 * variant + (1 if layer == 2 else 0)
		_meshes[key] = _star(points, radii[0], radii[1], seed_value)
	return _meshes[key]


static func _material_for(colour: Color, priority: int, depth_test: bool) -> StandardMaterial3D:
	var key := "%s|%d|%s" % [colour.to_html(), priority, depth_test]
	if not _materials.has(key):
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = colour
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		mat.billboard_keep_scale = true
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.no_depth_test = not depth_test
		mat.render_priority = priority
		_materials[key] = mat
	return _materials[key]


static func _layer(parent: Node3D, mesh: Mesh, size: float, colour: Color, priority: int, depth_test: bool) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.scale = Vector3.ONE * size
	mi.material_override = _material_for(colour, priority, depth_test)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


## A burst at a world position. size in metres (outer radius). depth_test false draws over geometry.
static func spawn(parent: Node, at: Vector3, colour: Color, size: float = 0.35, life: float = 0.16,
		points: int = 8, depth_test: bool = true) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var root := Node3D.new()
	parent.add_child(root)
	root.global_position = at
	_serial += 1
	var variant := _serial % VARIANTS
	var layers: Array[MeshInstance3D] = []
	layers.append(_layer(root, _mesh_for(points, 0, variant), size, Palette.hud_colour("ink"), 1, depth_test))
	layers.append(_layer(root, _mesh_for(points, 1, variant), size, Palette.under_ceiling(colour), 2, depth_test))
	layers.append(_layer(root, _mesh_for(points, 2, variant), size, Palette.hud_colour("paper"), 3, depth_test))
	root.scale = Vector3.ONE * 0.55
	var tw := root.create_tween()
	tw.set_parallel(true)
	tw.tween_property(root, "scale", Vector3.ONE, 0.05).set_ease(Tween.EASE_OUT)
	for l in layers:
		tw.tween_property(l, "transparency", 1.0, life).set_delay(0.04)
	tw.chain().tween_callback(root.queue_free)


## The impact star at the hit point, small (Sean: "a lot smaller"; these were 0.42 / 0.34 / 0.22).
static func spawn_impact(parent: Node, at: Vector3, hit_kind: int) -> void:
	match hit_kind:
		HitscanResolver.HEAD:
			spawn(parent, at, Palette.hud_colour("score"), 0.19, 0.2, 9)
		HitscanResolver.BODY:
			spawn(parent, at, Palette.hud_colour("paper"), 0.15, 0.16, 8)   # paper, not red (Sean)
		HitscanResolver.WORLD:
			spawn(parent, at, Palette.hud_colour("meter"), 0.10, 0.12, 7)


## Build the shared meshes and materials now (the pipeline warm-up at boot), so the first shot of
## a match creates nothing.
static func warm_up() -> void:
	for points in [7, 8, 9]:
		for layer in 3:
			for variant in VARIANTS:
				_mesh_for(points, layer, variant)
	for name in ["ink", "paper", "score", "meter"]:
		_material_for(Palette.hud_colour(name), 1, true)
		_material_for(Palette.hud_colour(name), 2, true)
		_material_for(Palette.hud_colour(name), 3, true)
