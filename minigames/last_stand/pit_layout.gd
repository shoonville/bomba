class_name PitLayout
extends RefCounted
## LAST STAND's own map: a 26 × 22 m pit, about a third of the gray-box's floor, so a one-life
## round forces meetings instead of two survivors never crossing paths in 60 s. One raised deck
## in the middle with steps on the south side, four low walls, eight crates, six edge spawns.
## Same rules as the gray-box: steps ≤ 1.2 m, saturated accent kept to two crates.


static func build() -> Dictionary:
	var W := 26.0
	var D := 22.0
	var boxes: Array = []
	boxes.append(GrayboxLayout.box(Vector3(0, -0.5, 0), Vector3(W, 1, D), "floor"))
	boxes.append(GrayboxLayout.box(Vector3(0, 3.0, -D / 2 - 0.5), Vector3(W + 2, 6, 1), "counter"))
	boxes.append(GrayboxLayout.box(Vector3(0, 3.0, D / 2 + 0.5), Vector3(W + 2, 6, 1), "counter"))
	boxes.append(GrayboxLayout.box(Vector3(-W / 2 - 0.5, 3.0, 0), Vector3(1, 6, D + 2), "counter_dark"))
	boxes.append(GrayboxLayout.box(Vector3(W / 2 + 0.5, 3.0, 0), Vector3(1, 6, D + 2), "counter_dark"))

	# Central deck with four posts that stand 1.25 m above it as cover, steps on the south side
	boxes.append(GrayboxLayout.box(Vector3(0, 2.75, 0), Vector3(6, 0.5, 6), "field_dark"))
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			boxes.append(GrayboxLayout.box(Vector3(sx * 2.5, 2.0, sz * 2.5), Vector3(0.6, 4, 0.6), "counter_dark"))
	boxes.append(GrayboxLayout.box(Vector3(0, 0.5, 5.5), Vector3(3, 1, 2), "field"))
	boxes.append(GrayboxLayout.box(Vector3(0, 1.5, 4.0), Vector3(3, 1, 1.5), "field"))
	boxes.append(GrayboxLayout.box(Vector3(0, 2.5, 3.0), Vector3(3, 1, 1.0), "field"))

	# Four low walls: chest height, so hip fights happen over them
	boxes.append(GrayboxLayout.box(Vector3(-8, 0.9, 0), Vector3(0.6, 1.8, 6), "counter"))
	boxes.append(GrayboxLayout.box(Vector3(8, 0.9, 0), Vector3(0.6, 1.8, 6), "counter"))
	boxes.append(GrayboxLayout.box(Vector3(0, 0.9, -7.5), Vector3(4, 1.8, 0.6), "counter"))
	boxes.append(GrayboxLayout.box(Vector3(0, 0.9, 7.5), Vector3(4, 1.8, 0.6), "counter"))

	# Crates off the waypoint lines
	var crates := [
		Vector3(-5, 0.6, 9.8), Vector3(5, 0.6, 9.8), Vector3(-5, 0.6, -9.8), Vector3(5, 0.6, -9.8),
		Vector3(-12, 0.6, 4), Vector3(12, 0.6, 4), Vector3(-12, 0.6, -4), Vector3(12, 0.6, -4),
	]
	for i in crates.size():
		boxes.append(GrayboxLayout.box(crates[i], Vector3(1.2, 1.2, 1.2), "accent" if i % 4 == 1 else "counter"))

	var spawns: Array = []
	for p in [Vector3(-11, 0, 9), Vector3(11, 0, 9), Vector3(-11, 0, -9), Vector3(11, 0, -9),
			Vector3(0, 0, 10), Vector3(0, 0, -10)]:
		var to_centre: Vector3 = Vector3.ZERO - p
		spawns.append({"pos": p, "yaw": atan2(-to_centre.x, -to_centre.z)})

	# Waypoints: a ring, four inner points, the south approach and the deck. Every edge is a
	# clear straight line (the walls and crates were placed around them).
	var wp := [
		Vector3(0, 0, 9),        # 0 south mid
		Vector3(0, 3.0, 0),      # 1 deck
		Vector3(0, 0, -9),       # 2 north mid
		Vector3(-10.5, 0, 0),    # 3 west lane
		Vector3(10.5, 0, 0),     # 4 east lane
		Vector3(-10.5, 0, 8),    # 5 SW
		Vector3(10.5, 0, 8),     # 6 SE
		Vector3(-10.5, 0, -8),   # 7 NW
		Vector3(10.5, 0, -8),    # 8 NE
		Vector3(-6, 0, 6),       # 9 inner SW
		Vector3(6, 0, 6),        # 10 inner SE
		Vector3(-6, 0, -6),      # 11 inner NW
		Vector3(6, 0, -6),       # 12 inner NE
	]
	var edges := [
		[0, 1], [0, 5], [0, 6], [2, 7], [2, 8], [5, 3], [3, 7], [6, 4], [4, 8],
		[9, 5], [10, 6], [11, 7], [12, 8], [9, 0], [10, 0], [11, 2], [12, 2], [9, 11], [10, 12],
	]
	var decor: Array = []
	GrayboxLayout.poster(decor, Vector3(-6, 3.0, -D / 2), Vector3(0, 0, 1), 2.6, 3.2, "poster_a", "accent")
	GrayboxLayout.poster(decor, Vector3(7, 3.0, D / 2), Vector3(0, 0, -1), 2.6, 3.2, "poster_b", "poster_a")
	GrayboxLayout.poster(decor, Vector3(-W / 2, 3.0, -3), Vector3(1, 0, 0), 2.6, 3.2, "accent", "poster_b")
	for lp in [Vector3(-12.2, 0, 9.5), Vector3(12.2, 0, -9.5)]:
		GrayboxLayout.lamp(decor, lp)
	return {"boxes": boxes, "spawns": spawns, "waypoints": wp, "edges": edges, "size": Vector2(W, D), "decor": decor}
