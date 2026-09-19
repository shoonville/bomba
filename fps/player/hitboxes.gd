class_name Hitboxes
extends RefCounted
## Builds the analytic hitboxes (head sphere + body capsule) of a player from its feet position.


static func sample_from(feet: Vector3, cfg: MovementConfig, alive: bool) -> HitboxHistory.Sample:
	var s := HitboxHistory.Sample.new()
	s.feet = feet
	s.head = feet + Vector3.UP * cfg.head_center_height
	s.body_a = feet + Vector3.UP * cfg.body_capsule_bottom
	s.body_b = feet + Vector3.UP * cfg.body_capsule_top
	s.head_r = cfg.head_radius
	s.body_r = cfg.body_capsule_radius
	s.alive = alive
	return s
