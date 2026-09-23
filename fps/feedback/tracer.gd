class_name Tracer
extends RefCounted
## Drawn shot feedback: a thin bar from muzzle to impact and a small impact mark, both fading
## fast. Shapes with flat colour, not particle glows (STYLE.md §5).
##
## One unit box mesh and one material per colour, shared (2026-09-22): a tracer used to build a
## BoxMesh and a StandardMaterial3D of its own on every shot, a new surface for the renderer to
## compile a pipeline for on the frame of the shot. The bar is the shared box scaled by the node
## and fades through GeometryInstance3D.transparency.

static var _mesh: BoxMesh
static var _materials: Dictionary = {}   # colour html -> StandardMaterial3D


static func _material_for(colour: Color) -> StandardMaterial3D:
	var key := colour.to_html()
	if not _materials.has(key):
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = colour
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_materials[key] = mat
	return _materials[key]


static func _unit_mesh() -> BoxMesh:
	if _mesh == null:
		_mesh = BoxMesh.new()
		_mesh.size = Vector3.ONE
	return _mesh


static func spawn(parent: Node, from: Vector3, to: Vector3, colour: Color, hit_kind: int, life: float = 0.12) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var length := (to - from).length()
	if length < 0.05:
		return
	var mi := MeshInstance3D.new()
	mi.mesh = _unit_mesh()
	mi.material_override = _material_for(Palette.under_ceiling(colour))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	mi.global_position = (from + to) * 0.5
	if absf((to - from).normalized().dot(Vector3.UP)) < 0.999:
		mi.look_at(to, Vector3.UP)
	else:
		mi.look_at(to, Vector3.RIGHT)
	mi.scale = Vector3(0.025, 0.025, length)
	var tw := parent.create_tween()
	tw.tween_property(mi, "transparency", 1.0, life)
	tw.tween_callback(mi.queue_free)
	if hit_kind != HitscanResolver.NONE:
		Burst.spawn_impact(parent, to, hit_kind)


## Build the shared mesh and the tracer materials for every player colour now (the pipeline
## warm-up at boot), so the first shot of a match creates nothing.
static func warm_up() -> void:
	_unit_mesh()
	for i in 6:
		_material_for(Palette.under_ceiling(Palette.player_colour(i)))
	_material_for(Palette.under_ceiling(Color.WHITE))
