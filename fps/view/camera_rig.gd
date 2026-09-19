class_name CameraRig
extends Node3D
## The local player's camera. Independent of the body node so mouse look is applied every frame
## from the raw accumulators (zero-lag), while position follows the tick-interpolated body.
## Recoil from weapon state and ADS FOV from the same scope_in_ticks the server enforces.

var player: Player
var camera: Camera3D
var viewmodel: Viewmodel
var post: PostStack
var base_fov: float = 62.0


func attach(p: Player) -> void:
	player = p
	base_fov = player.cfg.fov_vertical
	camera = Camera3D.new()
	camera.name = "Camera"
	camera.fov = base_fov
	camera.near = 0.04
	camera.far = 400.0
	camera.cull_mask = 0xFFFFF
	add_child(camera)
	camera.current = true
	viewmodel = Viewmodel.new()
	viewmodel.name = "Viewmodel"
	camera.add_child(viewmodel)
	viewmodel.setup(player)
	post = PostStack.new()
	post.name = "Post"
	camera.add_child(post)
	post.setup("arena")
	_sync()


func _process(_delta: float) -> void:
	if player == null or not is_instance_valid(player):
		return
	_sync()


func _sync() -> void:
	var inp := player.input
	var tick := NetworkTime.tick
	var ry := deg_to_rad(player.weapons.recoil_yaw)
	var rp := deg_to_rad(player.weapons.recoil_pitch)
	global_position = player.global_position + Vector3.UP * player.cfg.eye_height
	rotation = Vector3(inp.look_pitch + rp, inp.look_yaw + ry, 0.0)
	var def := player.weapons.current_def()
	var progress := Game.ads_progress_override(player.weapons.ads_progress(tick))
	# The rifle comes up first; the zoom happens behind the iris, from 55 % on.
	var zoom := smoothstep(0.55, 1.0, progress) if (def != null and def.is_sniper()) else 1.0 - pow(1.0 - progress, 2.0)
	if def != null:
		camera.fov = lerpf(base_fov, def.ads_fov_vertical, zoom)
	inp.ads_hint = progress > 0.5
