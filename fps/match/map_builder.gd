class_name MapBuilder
extends RefCounted
## Turns an ArenaLayout dictionary into StaticBody3D geometry with cel materials. No assets.


static func build(parent: Node3D, layout: Dictionary, map_id: String) -> void:
	var materials := {}
	for b in layout["boxes"]:
		var tone: String = b["tone"]
		if not materials.has(tone):
			materials[tone] = CelMaterial.for_tone(map_id, tone)
		var body := StaticBody3D.new()
		body.name = "Box_%d" % parent.get_child_count()
		body.collision_layer = 1
		body.collision_mask = 0
		body.position = b["pos"]
		var shape := CollisionShape3D.new()
		var box_shape := BoxShape3D.new()
		box_shape.size = b["size"]
		shape.shape = box_shape
		body.add_child(shape)
		var mesh := MeshInstance3D.new()
		var box_mesh := BoxMesh.new()
		box_mesh.size = b["size"]
		mesh.mesh = box_mesh
		mesh.material_override = materials[tone]
		mesh.layers = 1
		body.add_child(mesh)
		parent.add_child(body)
