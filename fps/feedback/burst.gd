class_name Burst
extends RefCounted
## Drawn feedback bursts (STYLE.md §5, the BRC boost burst): a spiky star built as three billboard
## triangle fans — ink rim, colour body, white core. Scales in fast, fades out faster. No particles.


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


static func _layer(parent: Node3D, mesh: Mesh, colour: Color, priority: int, depth_test: bool) -> StandardMaterial3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = colour
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.no_depth_test = not depth_test
	mat.render_priority = priority
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mat


## A burst at a world position. size in metres (outer radius). depth_test false draws over geometry.
static func spawn(parent: Node, at: Vector3, colour: Color, size: float = 0.35, life: float = 0.16,
		points: int = 8, depth_test: bool = true) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var root := Node3D.new()
	parent.add_child(root)
	root.global_position = at
	var seed_value := int(at.x * 131.0 + at.y * 17.0 + at.z * 7.0) + Time.get_ticks_msec()
	var ink := Palette.hud_colour("ink")
	var mats: Array[StandardMaterial3D] = []
	mats.append(_layer(root, _star(points, size * 1.18, size * 0.52, seed_value), ink, 1, depth_test))
	mats.append(_layer(root, _star(points, size, size * 0.42, seed_value), Palette.under_ceiling(colour), 2, depth_test))
	mats.append(_layer(root, _star(points, size * 0.48, size * 0.20, seed_value + 1), Palette.hud_colour("paper"), 3, depth_test))
	root.scale = Vector3.ONE * 0.55
	var tw := root.create_tween()
	tw.set_parallel(true)
	tw.tween_property(root, "scale", Vector3.ONE, 0.05).set_ease(Tween.EASE_OUT)
	for m in mats:
		tw.tween_property(m, "albedo_color:a", 0.0, life).set_delay(0.04)
	tw.chain().tween_callback(root.queue_free)


static func spawn_impact(parent: Node, at: Vector3, hit_kind: int) -> void:
	match hit_kind:
		HitscanResolver.HEAD:
			spawn(parent, at, Palette.hud_colour("score"), 0.42, 0.2, 9)
		HitscanResolver.BODY:
			spawn(parent, at, Palette.hud_colour("danger"), 0.34, 0.16, 8)
		HitscanResolver.WORLD:
			spawn(parent, at, Palette.hud_colour("meter"), 0.22, 0.12, 7)
