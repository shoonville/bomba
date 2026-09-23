class_name MapBuilder
extends RefCounted
## Turns a layout dictionary (GrayboxLayout or any minigame's own) into StaticBody3D geometry with cel materials. No assets.
##
## The boxes (collision) and the decor (meshes only) build separately so a match can spread
## the decor over ticks under the wipe (2026-09-22: the whole build in one frame stalled the
## wipe 90–200 ms); build() does both at once.


static func build(parent: Node3D, layout: Dictionary, map_id: String) -> void:
	build_boxes(parent, layout, map_id)
	build_decor(parent, layout, map_id, 0, layout.get("decor", []).size())


## Decor entries [from, to) of the layout: posters, lamp posts, road paint, hazard stripes, the
## city. Meshes only, no collision.
static func build_decor(parent: Node3D, layout: Dictionary, map_id: String, from: int, to: int) -> void:
	var decor: Array = layout.get("decor", [])
	for i in range(maxi(from, 0), mini(to, decor.size())):
		var dcr: Dictionary = decor[i]
		var tone: String = dcr["tone"]
		# Building masses (the skyline, big façades) take the wall print: storey and panel seams.
		var dsize: Vector3 = dcr["size"]
		var dkind := ""
		if str(dcr.get("shape", "box")) == "box" and dsize.y >= 5.0 and maxf(dsize.x, dsize.z) >= 5.0 \
				and tone in ["skyline", "counter", "counter_dark", "field", "field_dark"]:
			dkind = "wall"
		var mi := MeshInstance3D.new()
		if str(dcr.get("shape", "box")) == "cylinder":
			var cm := CylinderMesh.new()
			cm.top_radius = (dcr["size"] as Vector3).x * 0.5
			cm.bottom_radius = (dcr["size"] as Vector3).z * 0.5
			cm.height = (dcr["size"] as Vector3).y
			cm.radial_segments = 10
			mi.mesh = cm
		else:
			mi.mesh = unit_box()
			mi.scale = dcr["size"]
		mi.position = dcr["pos"]
		if dcr.has("yaw"):
			mi.rotation.y = float(dcr["yaw"])
		if dcr.has("roll"):
			mi.rotation.z = float(dcr["roll"])   # a cylinder rolled onto its side, its length along X (a pipe)
		if not bool(dcr.get("shadow", true)):
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF   # skyline, thin façade details
		mi.material_override = CelMaterial.for_tone(map_id, tone, dkind)   # cached per map, tone and print
		mi.layers = 1
		parent.add_child(mi)


static var _unit_box: BoxMesh


## One unit box for every box on the map, scaled by the node (the print layer is world-space, so
## the seams do not stretch): 171 boxes used to be 171 meshes, each its own GPU buffers uploaded
## on the first frame of the match (2026-09-22).
static func unit_box() -> BoxMesh:
	if _unit_box == null:
		_unit_box = BoxMesh.new()
		_unit_box.size = Vector3.ONE
	return _unit_box


## The layout's boxes: static bodies with a box shape and a cel mesh; the floor and anything
## wall sized take the print layer.
static func build_boxes(parent: Node3D, layout: Dictionary, map_id: String) -> void:
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
		mesh.mesh = unit_box()
		mesh.scale = b["size"]
		mesh.material_override = CelMaterial.for_tone(map_id, tone, print_kind)
		mesh.layers = 1
		body.add_child(mesh)
		parent.add_child(body)
