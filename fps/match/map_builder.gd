class_name MapBuilder
extends RefCounted
## Turns a layout dictionary (GrayboxLayout or any minigame's own) into StaticBody3D geometry with cel materials. No assets.


static func build(parent: Node3D, layout: Dictionary, map_id: String) -> void:
	var materials := {}
	# Decor: meshes only, no collision. Posters, lamp posts, road paint, hazard stripes.
	for dcr in layout.get("decor", []):
		var tone: String = dcr["tone"]
		if not materials.has(tone):
			materials[tone] = CelMaterial.for_tone(map_id, tone)
		var mi := MeshInstance3D.new()
		if str(dcr.get("shape", "box")) == "cylinder":
			var cm := CylinderMesh.new()
			cm.top_radius = (dcr["size"] as Vector3).x * 0.5
			cm.bottom_radius = (dcr["size"] as Vector3).z * 0.5
			cm.height = (dcr["size"] as Vector3).y
			cm.radial_segments = 10
			mi.mesh = cm
		else:
			var bm := BoxMesh.new()
			bm.size = dcr["size"]
			mi.mesh = bm
		mi.position = dcr["pos"]
		if dcr.has("yaw"):
			mi.rotation.y = float(dcr["yaw"])
		if dcr.has("roll"):
			mi.rotation.z = float(dcr["roll"])   # a cylinder rolled onto its side, its length along X (a pipe)
		if not bool(dcr.get("shadow", true)):
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF   # skyline, thin façade details
		mi.material_override = materials[tone]
		mi.layers = 1
		parent.add_child(mi)
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
