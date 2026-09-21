class_name AnnexPlan
extends RefCounted
## Where a board's two annexes stand: the angle round the rim where the walkway sits farthest
## from it, then the best angle at least APART_DEG away. Shared by board_dressing.gd (which
## builds the annexes there) and tools/mark_spots.gd (which flags the space nearest each as a
## machine spot), so the annexes and the machine spots stay one thing. No dependencies: the tool
## runs as a --script without the autoloads.

const ANGLES := 36         # candidate angles round the rim
const APART_DEG := 110.0   # the two annexes stand at least this far apart


## `tiles` are the spaces' positions (Vector3, y ignored); `centre`, `rx`, `rz` the moon slab's
## ellipse. Returns one or two angles, the better first.
static func angles(tiles: Array, centre: Vector3, rx: float, rz: float) -> Array:
	var clearance: Array = []
	for i in ANGLES:
		var a := i * TAU / ANGLES
		var rim := Vector2(centre.x + cos(a) * rx, centre.z + sin(a) * rz)
		var d := 1e9
		for p in tiles:
			d = minf(d, Vector2(p.x - rim.x, p.z - rim.y).length())
		clearance.append(d)
	var best_i := 0
	for i in ANGLES:
		if clearance[i] > clearance[best_i]:
			best_i = i
	var second_i := -1
	for i in ANGLES:
		var apart := absf(wrapf((i - best_i) * TAU / ANGLES, -PI, PI))
		if apart >= deg_to_rad(APART_DEG) and (second_i < 0 or clearance[i] > clearance[second_i]):
			second_i = i
	var out: Array = [best_i * TAU / ANGLES]
	if second_i >= 0:
		out.append(second_i * TAU / ANGLES)
	return out
