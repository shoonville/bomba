class_name AnnexPlan
extends RefCounted
## Where a board's two annexes stand: the angle round the rim where the walkway sits farthest
## from it, then the best angle at least APART_DEG away. Shared by board_dressing.gd (which
## builds the annexes there) and tools/mark_spots.gd (which flags the space nearest each as a
## machine spot), so the annexes and the machine spots stay one thing. On the district board the
## slab's margin is widest at the west and east rims (tools/gen_board.gd, MARGIN_X over
## MARGIN_Z), so the annexes stand off the middle of those two sides. No dependencies: the tool
## runs as a --script without the autoloads.

const ANGLES := 36         # candidate angles round the rim
const APART_DEG := 110.0   # the two annexes stand at least this far apart


## `tiles` are the spaces' positions (Vector3, y ignored); `slab` the moon chunk's outline; a board
## that names its own angles (`preset`, the district's "annexes": the two ends of main street)
## gets them back as they are. Returns one or two angles, the better first.
static func angles(tiles: Array, slab: MoonSlab, preset: Array = []) -> Array:
	if not preset.is_empty():
		var out_p: Array = []
		for a in preset:
			out_p.append(float(a))
		return out_p
	var clearance: Array = []
	for i in ANGLES:
		var rim := slab.rim(i * TAU / ANGLES)
		var d := 1e9
		for p in tiles:
			d = minf(d, Vector2(p.x - rim.x, p.z - rim.y).length())
		clearance.append(d)
	var best_i := 0
	for i in ANGLES:
		if clearance[i] > clearance[best_i] + 0.01:
			best_i = i
	var second_i := -1
	for i in ANGLES:
		var apart := absf(wrapf((i - best_i) * TAU / ANGLES, -PI, PI))
		if apart >= deg_to_rad(APART_DEG) and (second_i < 0 or clearance[i] > clearance[second_i] + 0.01):
			second_i = i
	var out: Array = [best_i * TAU / ANGLES]
	if second_i >= 0:
		out.append(second_i * TAU / ANGLES)
	return out
