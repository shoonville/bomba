class_name HitscanResolver
extends RefCounted
## Lag-compensated hitscan. World geometry is tested with one physics raycast (world layer
## only); players are tested analytically against their HitboxHistory rewound to the shooter's
## view tick. Runs identically on the shooter's client and on the server.

enum { NONE = 0, WORLD = 1, BODY = 2, HEAD = 3 }


class Target:
	var id: int = 0
	var node: Node = null
	var history: HitboxHistory = null


class Result:
	var kind: int = NONE
	var target_id: int = 0
	var target: Node = null
	var point: Vector3 = Vector3.ZERO
	var normal: Vector3 = Vector3.UP
	var distance: float = 0.0
	var hit_height: float = 0.0  # metres above the victim's feet


static func resolve(space: PhysicsDirectSpaceState3D, origin: Vector3, dir: Vector3, max_range: float,
		view_tick: float, targets: Array, world_mask: int) -> Result:
	var r := Result.new()
	var best_t := max_range
	r.point = origin + dir * max_range
	r.distance = max_range
	if space != null:
		var q := PhysicsRayQueryParameters3D.create(origin, origin + dir * max_range, world_mask)
		q.collide_with_areas = false
		q.hit_from_inside = false
		var hit := space.intersect_ray(q)
		if not hit.is_empty():
			r.kind = WORLD
			r.point = hit["position"]
			r.normal = hit["normal"]
			best_t = (r.point - origin).length()
			r.distance = best_t
	for tgt in targets:
		var t: Target = tgt
		if t.history == null:
			continue
		var s := t.history.sample_at(view_tick)
		if s == null or not s.alive:
			continue
		var kind := NONE
		var th := HitscanMath.ray_sphere(origin, dir, s.head, s.head_r)
		var hit_t := -1.0
		if th >= 0.0:
			hit_t = th
			kind = HEAD
		else:
			var tb := HitscanMath.ray_capsule(origin, dir, s.body_a, s.body_b, s.body_r)
			if tb >= 0.0:
				hit_t = tb
				kind = BODY
		if kind != NONE and hit_t < best_t:
			best_t = hit_t
			r.kind = kind
			r.target_id = t.id
			r.target = t.node
			r.point = origin + dir * hit_t
			r.distance = hit_t
			r.hit_height = r.point.y - s.feet.y
	return r


static func kind_name(kind: int) -> String:
	match kind:
		WORLD: return "world"
		BODY: return "body"
		HEAD: return "head"
	return "none"
