class_name MapBuilder
extends RefCounted
## Turns a layout dictionary (GrayboxLayout or any minigame's own) into StaticBody3D geometry with cel materials. No assets.


static func build(parent: Node3D, layout: Dictionary, map_id: String) -> void:
	var materials := {}
	# Decor: meshes only, no collision. Posters, lamp posts, road paint, hazard stripes.
	for dcr in layout.get("decor", []):
		var tone: String = dcr["tone"]
		# Building masses (the skyline, big façades) take the wall print: storey and panel seams.
		var dsize: Vector3 = dcr["size"]
		var dkind := ""
		if str(dcr.get("shape", "box")) == "box" and dsize.y >= 5.0 and maxf(dsize.x, dsize.z) >= 5.0 \
				and tone in ["skyline", "counter", "counter_dark", "field", "field_dark"]:
			dkind = "wall"
		var dkey := "%s/%s" % [tone, dkind]
		if not materials.has(dkey):
			materials[dkey] = CelMaterial.for_tone(map_id, tone, dkind)
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
		mi.material_override = materials[dkey]
		mi.layers = 1
		parent.add_child(mi)
	for b in layout["boxes"]:
		var tone: String = b["tone"]
		# The print layer goes on the big flat surfaces: the floor gets paving seams, anything wall
		# sized (2.5 m tall and 4 m long) gets panel seams; crates and steps stay plain.
		var size: Vector3 = b["size"]
		var print_kind := ""
		if tone == "floor":
			print_kind = "floor"
		elif size.y >= 2.5 and maxf(size.x, size.z) >= 4.0:
			print_kind = "wall"
		var mat_key := "%s/%s" % [tone, print_kind]
		if not materials.has(mat_key):
			materials[mat_key] = CelMaterial.for_tone(map_id, tone, print_kind)
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
		mesh.material_override = materials[mat_key]
		mesh.layers = 1
		body.add_child(mesh)
		parent.add_child(body)
