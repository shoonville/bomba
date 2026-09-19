class_name Tracer
extends RefCounted
## Drawn shot feedback: a thin bar from muzzle to impact and a small impact mark, both fading
## fast. Shapes with flat colour, not particle glows (STYLE.md §5).


static func spawn(parent: Node, from: Vector3, to: Vector3, colour: Color, hit_kind: int, life: float = 0.12) -> void:
	if parent == null:
		return
	var length := (to - from).length()
	if length < 0.05:
		return
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.025, 0.025, length)
	mi.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Palette.under_ceiling(colour)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	var mid := (from + to) * 0.5
	mi.global_position = mid
	if absf((to - from).normalized().dot(Vector3.UP)) < 0.999:
		mi.look_at(to, Vector3.UP)
	else:
		mi.look_at(to, Vector3.RIGHT)
	var tw := parent.create_tween()
	tw.tween_property(mat, "albedo_color:a", 0.0, life)
	tw.tween_callback(mi.queue_free)
	if hit_kind != HitscanResolver.NONE:
		Burst.spawn_impact(parent, to, hit_kind)
