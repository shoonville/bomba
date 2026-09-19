class_name SpawnSelector
extends RefCounted
## Picks a spawn that no enemy can see and that is far from enemies (DESIGN.md §5). Pure
## scoring over the layout's spawn list; the LOS test is a physics raycast on the world layer.

var spawns: Array = []
var min_enemy_distance: float = 7.0
var los_penalty: float = 100.0
var distance_weight: float = 1.0
var recent_penalty: float = 25.0
var eye_height: float = 1.62
var world_mask: int = 1

var _recent: Dictionary = {}  # spawn index -> tick last used


func configure(p_spawns: Array, arena_cfg: Dictionary, p_eye_height: float) -> void:
	spawns = p_spawns
	min_enemy_distance = float(arena_cfg.get("spawn_min_enemy_distance_m", 7.0))
	los_penalty = float(arena_cfg.get("spawn_los_penalty", 100.0))
	distance_weight = float(arena_cfg.get("spawn_distance_weight", 1.0))
	recent_penalty = float(arena_cfg.get("spawn_recent_penalty", 25.0))
	eye_height = p_eye_height


## enemies: Array of eye positions (Vector3). Returns {pos, yaw, index}.
func pick(enemies: Array, space: PhysicsDirectSpaceState3D, tick: int, rng: RandomNumberGenerator) -> Dictionary:
	if spawns.is_empty():
		return {"pos": Vector3.ZERO, "yaw": 0.0, "index": -1}
	var best_i := -1
	var best_score := -1e18
	var order := range(spawns.size())
	# Deterministic tie-break: shuffle the evaluation order with the seeded generator.
	for i in range(order.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = order[i]
		order[i] = order[j]
		order[j] = tmp
	for i in order:
		var sp: Dictionary = spawns[i]
		var pos: Vector3 = sp["pos"]
		var eye := pos + Vector3.UP * eye_height
		var score := 0.0
		var nearest := 1e9
		for e in enemies:
			var d: float = (e - pos).length()
			nearest = minf(nearest, d)
			if space != null:
				var q := PhysicsRayQueryParameters3D.create(eye, e, world_mask)
				if space.intersect_ray(q).is_empty():
					score -= los_penalty
		if enemies.is_empty():
			nearest = 30.0
		score += distance_weight * minf(nearest, 30.0)
		if nearest < min_enemy_distance:
			score -= los_penalty
		if _recent.has(i) and tick - int(_recent[i]) < 600:
			score -= recent_penalty
		if score > best_score:
			best_score = score
			best_i = i
	_recent[best_i] = tick
	var chosen: Dictionary = spawns[best_i]
	return {"pos": chosen["pos"], "yaw": float(chosen["yaw"]), "index": best_i}
