class_name HillRules
extends RefCounted
## KING OF THE HILL's rules as pure functions, so they are unit-tested and the match node only
## wires them to ticks, RPCs and meshes.

const EMPTY := 0                    # nobody inside
const CONTESTED := -(1 << 30)      # two or more inside (bots are small negative ids, humans positive)


## A player (position at the feet) is inside a hill cylinder: within `radius` of its centre
## on the ground plane, from `floor_slack` under the hill's floor up to `height` over it.
static func inside(pos: Vector3, hill: Vector3, radius: float, height: float, floor_slack: float = 0.3) -> bool:
	if pos.y < hill.y - floor_slack or pos.y > hill.y + height:
		return false
	return Vector2(pos.x - hill.x, pos.z - hill.z).length_squared() <= radius * radius


## Who scores this tick: the one id alone inside, EMPTY for an empty hill, CONTESTED otherwise.
static func holder(inside_ids: Array) -> int:
	if inside_ids.is_empty():
		return EMPTY
	if inside_ids.size() > 1:
		return CONTESTED
	return int(inside_ids[0])


## A visiting order of the `n` spots: a seeded permutation that never starts on `avoid` (the spot
## just left) when there is a choice, or on `first` when it is pinned (the harness).
static func make_order(n: int, rng: RandomNumberGenerator, avoid: int = -1, first: int = -1) -> Array:
	var order: Array = []
	for i in n:
		order.append(i)
	for i in range(n - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t: Variant = order[i]
		order[i] = order[j]
		order[j] = t
	if first >= 0 and first < n:
		order.erase(first)
		order.push_front(first)
	elif n > 1 and int(order[0]) == avoid:
		order.push_back(order.pop_front())
	return order


static func format_seconds(ticks: int, tickrate: int) -> String:
	var secs := ticks / maxi(1, tickrate)
	return "%d:%02d" % [secs / 60, secs % 60]
