class_name SpectatorRig
extends Node3D
## Chase camera for an eliminated player: sits behind and above a living player, looks where
## they look, and cycles to the next living player on fire. Same post stack as the first-person
## camera so the picture does not change style when you die.

var camera: Camera3D
var post: PostStack
var target: Player
var _pick: Callable  # (current: Player, step: int) -> Player
var world_mask: int = 1
var _smooth_pos: Vector3
var _smooth_yaw: float = 0.0
var _started: bool = false


func setup(picker: Callable, first: Player, p_world_mask: int = 1) -> void:
	_pick = picker
	world_mask = p_world_mask
	camera = Camera3D.new()
	camera.name = "Camera"
	camera.fov = 58.0
	camera.near = 0.05
	camera.far = 400.0
	add_child(camera)
	post = PostStack.new()
	post.name = "Post"
	camera.add_child(post)
	post.setup("arena")
	camera.current = true
	target = first


func target_name() -> String:
	return target.display_name if target != null and is_instance_valid(target) else ""


func cycle(step: int) -> void:
	var next: Player = _pick.call(target, step)
	if next != null and next != target:
		target = next
		_started = false


func _process(delta: float) -> void:
	if target == null or not is_instance_valid(target) or not target.is_inside_tree() or not target.is_alive():
		var next: Player = _pick.call(target, 1)
		if next == null:
			return
		target = next
		_started = false
	var yaw := target.yaw
	var pitch := target.head_pitch
	var back := Vector3(sin(yaw), 0.0, cos(yaw))  # behind the target (its forward is -sin, -cos)
	var eye := target.eye_position()
	var want_pos := eye + back * 2.6 + Vector3.UP * 0.9
	# Spring arm: never put the camera inside the map. Pull in to the first wall on the way back.
	var space := get_world_3d().direct_space_state
	if space != null:
		var q := PhysicsRayQueryParameters3D.create(eye, want_pos + (want_pos - eye).normalized() * 0.3)
		q.collision_mask = world_mask
		var hit := space.intersect_ray(q)
		if not hit.is_empty():
			want_pos = eye + (hit["position"] - eye) * 0.9
	if not _started:
		_smooth_pos = want_pos
		_smooth_yaw = yaw
		_started = true
	var k := 1.0 - pow(0.001, delta)  # ~99.9 % of the way in one second
	_smooth_pos = _smooth_pos.lerp(want_pos, k)
	_smooth_yaw = lerp_angle(_smooth_yaw, yaw, k)
	global_position = _smooth_pos
	rotation = Vector3(clampf(pitch * 0.6, -0.6, 0.35), _smooth_yaw, 0.0)
