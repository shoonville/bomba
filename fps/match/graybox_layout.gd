class_name ArenaLayout
extends RefCounted
## The gray-box arena as data: boxes, spawns, bot waypoints. Built to Rust's principles
## (DESIGN.md §5) at ~125 % footprint with added vertical: one central tower everyone orbits,
## two rooftops for the sniper, cover lanes along the edges for the flank.
## Units: metres. Y up. Steps are ≤ 1.2 m so a 1.49 m Halo jump clears them.


static func box(pos: Vector3, size: Vector3, tone: String = "field") -> Dictionary:
	return {"pos": pos, "size": size, "tone": tone}


static func build() -> Dictionary:
	var W := 48.0
	var D := 40.0
	var boxes: Array = []
	# Floor and perimeter
	boxes.append(box(Vector3(0, -0.5, 0), Vector3(W, 1, D), "floor"))
	boxes.append(box(Vector3(0, 3.0, -D / 2 - 0.5), Vector3(W + 2, 6, 1), "counter"))
	boxes.append(box(Vector3(0, 3.0, D / 2 + 0.5), Vector3(W + 2, 6, 1), "counter"))
	boxes.append(box(Vector3(-W / 2 - 0.5, 3.0, 0), Vector3(1, 6, D + 2), "counter_dark"))
	boxes.append(box(Vector3(W / 2 + 0.5, 3.0, 0), Vector3(1, 6, D + 2), "counter_dark"))

	# Central tower: three decks, pillars, stepped access on two sides
	boxes.append(box(Vector3(0, 2.75, 0), Vector3(7, 0.5, 7), "field_dark"))
	boxes.append(box(Vector3(0, 5.75, 0), Vector3(6, 0.5, 6), "field_dark"))
	boxes.append(box(Vector3(0, 8.75, 0), Vector3(4.5, 0.5, 4.5), "accent"))
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			boxes.append(box(Vector3(sx * 3.0, 4.5, sz * 3.0), Vector3(0.6, 9, 0.6), "counter_dark"))
	# Deck 1 access: 3 steps on the south (+z) side
	boxes.append(box(Vector3(0, 0.5, 6.5), Vector3(3, 1, 2), "field"))
	boxes.append(box(Vector3(0, 1.5, 5.0), Vector3(3, 1, 1.5), "field"))
	boxes.append(box(Vector3(0, 2.5, 4.0), Vector3(3, 1, 1.0), "field"))
	# Deck 1 → deck 2: crates on the north (-z) edge of deck 1
	boxes.append(box(Vector3(2.0, 3.6, -2.5), Vector3(1.4, 1.2, 1.4), "field_dark"))
	boxes.append(box(Vector3(-2.0, 4.8, -2.5), Vector3(1.4, 1.2, 1.4), "field_dark"))
	# Deck 2 → deck 3: crate on the east edge
	boxes.append(box(Vector3(2.4, 6.6, 1.5), Vector3(1.2, 1.2, 1.2), "field_dark"))
	boxes.append(box(Vector3(2.4, 7.8, -0.5), Vector3(1.2, 1.2, 1.2), "field_dark"))

	# Two buildings (rooftops = sniper perches), opposite corners, with crate stairs
	for s: float in [-1.0, 1.0]:
		var bx: float = s * 16.0
		var bz: float = s * -12.0
		boxes.append(box(Vector3(bx, 2.0, bz), Vector3(9, 4, 8), "field"))
		boxes.append(box(Vector3(bx - s * 6.5, 0.6, bz + 2.0), Vector3(1.6, 1.2, 1.6), "field_dark"))
		boxes.append(box(Vector3(bx - s * 6.5, 1.8, bz + 0.2), Vector3(1.6, 1.2, 1.6), "field_dark"))
		boxes.append(box(Vector3(bx - s * 6.5, 3.0, bz - 1.6), Vector3(1.6, 1.2, 1.6), "field_dark"))
		# Low parapet on the roof for cover
		boxes.append(box(Vector3(bx, 4.4, bz + s * 3.8), Vector3(9, 0.8, 0.4), "field_dark"))

	# Cover lanes: long low walls east/west of the tower, mid-height walls north/south
	boxes.append(box(Vector3(-10, 1.25, 0), Vector3(0.6, 2.5, 10), "counter"))
	boxes.append(box(Vector3(10, 1.25, 0), Vector3(0.6, 2.5, 10), "counter"))
	boxes.append(box(Vector3(0, 0.9, -13), Vector3(12, 1.8, 0.6), "counter"))
	boxes.append(box(Vector3(0, 0.9, 13), Vector3(12, 1.8, 0.6), "counter"))

	# Scattered crates: jump-height hops and sightline breakers
	var crates := [
		Vector3(-18, 0.6, 10), Vector3(-16.6, 0.6, 10), Vector3(-17.3, 1.8, 10),
		Vector3(18, 0.6, -6), Vector3(19.2, 0.6, -6), Vector3(18.6, 1.8, -6),
		Vector3(-6, 0.6, -16), Vector3(6, 0.6, 16), Vector3(14, 0.6, 8), Vector3(-14, 0.6, -8),
		Vector3(-3, 0.6, 12), Vector3(3, 0.6, -12),
	]
	for i in crates.size():
		# A few crates carry the accent; most are the counter colour so the accent stays small.
		boxes.append(box(crates[i], Vector3(1.2, 1.2, 1.2), "accent" if i % 4 == 2 else "counter"))

	# A catwalk along the east wall at 3.6 m with step access at both ends
	boxes.append(box(Vector3(21.5, 3.4, 0), Vector3(3, 0.4, 24), "field_dark"))
	boxes.append(box(Vector3(21.5, 0.6, 13.5), Vector3(3, 1.2, 1.5), "field"))
	boxes.append(box(Vector3(21.5, 1.8, 12.5), Vector3(3, 1.2, 1.0), "field"))
	boxes.append(box(Vector3(21.5, 2.8, 11.7), Vector3(3, 1.2, 0.8), "field"))
	boxes.append(box(Vector3(21.5, 0.6, -13.5), Vector3(3, 1.2, 1.5), "field"))
	boxes.append(box(Vector3(21.5, 1.8, -12.5), Vector3(3, 1.2, 1.0), "field"))
	boxes.append(box(Vector3(21.5, 2.8, -11.7), Vector3(3, 1.2, 0.8), "field"))

	# Spawn points: {pos, yaw} — yaw faces the centre. Ground level, edges, one on each roof.
	var spawns: Array = []
	var spawn_positions := [
		Vector3(-20, 0, 16), Vector3(20, 0, 16), Vector3(-20, 0, -16), Vector3(20, 0, -16),
		Vector3(0, 0, 17), Vector3(0, 0, -17), Vector3(-21, 0, 0), Vector3(21.5, 3.6, 0),
		Vector3(16, 4.0, -12), Vector3(-16, 4.0, 12),
	]
	for p in spawn_positions:
		var to_centre: Vector3 = Vector3(0, 0, 0) - p
		spawns.append({"pos": p, "yaw": atan2(-to_centre.x, -to_centre.z)})

	# Bot waypoints and edges (a hand-made graph; straight lines between linked points are clear)
	var wp := [
		Vector3(0, 0, 9),        # 0 south of tower steps
		Vector3(0, 3.0, 0),      # 1 deck 1
		Vector3(0, 6.0, 0),      # 2 deck 2
		Vector3(-14, 0, 0),      # 3 west lane
		Vector3(14, 0, 0),       # 4 east lane
		Vector3(0, 0, -9),       # 5 north of tower
		Vector3(-20, 0, 16),     # 6 SW corner
		Vector3(20, 0, 16),      # 7 SE corner
		Vector3(-20, 0, -16),    # 8 NW corner
		Vector3(20, 0, -16),     # 9 NE corner
		Vector3(0, 0, 17),       # 10 south edge
		Vector3(0, 0, -17),      # 11 north edge
		Vector3(21.5, 3.6, 0),   # 12 catwalk middle
		Vector3(21.5, 0, 16),    # 13 catwalk south foot
		Vector3(21.5, 0, -16),   # 14 catwalk north foot
		Vector3(-8, 0, 8),       # 15 SW inner
		Vector3(8, 0, 8),        # 16 SE inner
		Vector3(-8, 0, -8),      # 17 NW inner
		Vector3(8, 0, -8),       # 18 NE inner
	]
	var edges := [
		[0, 1], [1, 2], [0, 15], [0, 16], [0, 10], [5, 17], [5, 18], [5, 11],
		[15, 3], [17, 3], [16, 4], [18, 4], [15, 6], [16, 7], [17, 8], [18, 9],
		[6, 10], [7, 10], [8, 11], [9, 11], [7, 13], [13, 12], [12, 14], [14, 9],
		[3, 6], [3, 8], [4, 7], [4, 9], [15, 17], [16, 18],
	]
	return {"boxes": boxes, "spawns": spawns, "waypoints": wp, "edges": edges, "size": Vector2(W, D)}
