class_name KillCam
extends Node3D
## The final kill, replayed from the killer's eyes (Sean, 2026-09-22: "a final kill kill cam like
## they do in COD"): the last seconds before the kill from the replay buffer every body keeps
## (Player.replay_sample), the killer's weapon in view, the shot as a tracer at the kill tick,
## the victim falling. Presentation only, on every peer from its own buffers.

const BEFORE_TICKS := 150   # 2.5 s before the kill
const AFTER_TICKS := 48     # 0.8 s after it
const SECONDS := float(BEFORE_TICKS + AFTER_TICKS) / 60.0

var finished: bool = false
var _arena: Node
var _killer: Player
var _victim: Player
var _kill_tick: int = 0
var _weapon: String = "ar"
var _headshot: bool = false
var _eye: float = 1.62
var _t: float = 0.0
var _camera: Camera3D
var _viewmodel: Viewmodel
var _shot_done: bool = false
var _others: Array = []      # PlayerVisual of everyone but the killer
var _killer_visual: Node3D
var _local_viewmodel: Node3D   # this peer's own first-person weapon, hidden for the replay
var _def: WeaponDef           # the weapon the kill was made with: its scope-in zoom
var _base_fov: float = 62.0
var ads_progress: float = 0.0   # the killer's replayed scope-in, for the HUD's scope overlay


func setup(arena: Node, killer: Player, victim: Player, kill_tick: int, weapon: String, headshot: bool, eye_height: float) -> void:
	_arena = arena
	_killer = killer
	_victim = victim
	_kill_tick = kill_tick
	_weapon = weapon
	_headshot = headshot
	_eye = eye_height
	_camera = Camera3D.new()
	_camera.name = "KillCamera"
	_camera.fov = killer.cfg.fov_vertical if killer.cfg != null else 62.0
	_camera.near = 0.04
	_camera.far = 400.0
	_camera.cull_mask = 0xFFFFF
	add_child(_camera)
	_camera.current = true
	var post := PostStack.new()
	post.name = "Post"
	_camera.add_child(post)
	post.setup("arena")
	# The killer's weapon, as a ghost: the slot they killed with, no scope-in, no bob.
	_viewmodel = Viewmodel.new()
	_viewmodel.name = "Viewmodel"
	_camera.add_child(_viewmodel)
	_viewmodel.setup(killer)
	var slot := 0
	for i in killer.weapons.defs.size():
		if killer.weapons.defs[i].id == weapon:
			slot = i
	_viewmodel.ghost_slot = slot
	_def = killer.weapons.def_for_slot(slot)
	_base_fov = _camera.fov
	# This peer's own hands and gun sit at its live eye position; every layer is in view here, so
	# they would show as a floating weapon where that player ended the round (Sean, 2026-09-23).
	_local_viewmodel = arena.local_viewmodel() if arena.has_method("local_viewmodel") else null
	if _local_viewmodel != null:
		_local_viewmodel.visible = false
	for p in arena.all_player_nodes():
		var pl := p as Player
		for child in pl.visual.get_children():
			if child is PlayerVisual:
				if pl == killer:
					_killer_visual = child
					child.visible = false   # first person: the killer's own body stays out of shot
				else:
					child.begin_replay()
					_others.append(child)
	_place(float(_kill_tick - BEFORE_TICKS))


func _process(delta: float) -> void:
	if finished:
		return
	_t += delta
	var pt := float(_kill_tick - BEFORE_TICKS) + _t * NetworkTime.tickrate
	if pt >= float(_kill_tick + AFTER_TICKS):
		finished = true
		return
	_place(pt)
	if not _shot_done and pt >= float(_kill_tick):
		_shot_done = true
		_fire()


## Everyone where they were at replay tick `pt`.
func _place(pt: float) -> void:
	var k := _killer.replay_sample(pt)
	if not k.is_empty():
		_camera.global_position = k["pos"] + Vector3.UP * _eye
		_camera.rotation = Vector3(k["pitch"], k["yaw"], 0.0)
		# The scope-in as the killer had it (Sean, 2026-09-23): the rifle comes up, then the zoom
		# behind the iris, the CameraRig's own curve; the HUD draws the iris from ads_progress.
		ads_progress = float(k.get("ads", 0.0))
		_viewmodel.ghost_ads = ads_progress
		if _def != null:
			var zoom := smoothstep(0.55, 1.0, ads_progress) if _def.is_sniper() else 1.0 - pow(1.0 - ads_progress, 2.0)
			_camera.fov = lerpf(_base_fov, _def.ads_fov_vertical, zoom)
	for v in _others:
		var vis := v as PlayerVisual
		if vis.player == null or not is_instance_valid(vis.player):
			continue
		var s := vis.player.replay_sample(pt)
		if not s.is_empty():
			vis.replay_pose(s["pos"], s["yaw"], s["pitch"], int(s["health"]) > 0)
	if _arena.has_method("killcam_place"):
		_arena.killcam_place(pt)   # anything else in the shot (FIREBALL's ball) where it was


## The shot: the killer's tracer from the ghost weapon's muzzle to the victim, the impact star,
## the weapon's sound and the kick.
func _fire() -> void:
	if _arena.has_method("killcam_fire") and _arena.killcam_fire(_weapon):
		return   # the minigame played the kill's moment (FIREBALL: the ball bursts, no shot)
	var s := _victim.replay_sample(float(_kill_tick))
	if s.is_empty():
		return
	var at: Vector3 = s["pos"] + Vector3.UP * (_eye if _headshot else _eye * 0.7)
	var from := _viewmodel.muzzle_world()
	var effects: Node = _arena.effects_root if "effects_root" in _arena else self
	Tracer.spawn(effects, from, at, _killer.colour, HitscanResolver.HEAD if _headshot else HitscanResolver.BODY)
	_viewmodel.kick()
	Audio.play("sniper_fire" if _weapon == "sniper" else "ar_fire", 0.0)
	Audio.play("headshot" if _headshot else "hitmarker", -2.0)


## Hand the view back: figures follow their bodies again, the killer's shows again.
func end() -> void:
	for v in _others:
		if is_instance_valid(v):
			(v as PlayerVisual).end_replay()
	if _killer_visual != null and is_instance_valid(_killer_visual):
		_killer_visual.visible = true
	if _local_viewmodel != null and is_instance_valid(_local_viewmodel):
		_local_viewmodel.visible = true
	if _camera != null:
		_camera.current = false
	if _arena != null and is_instance_valid(_arena) and _arena.has_method("killcam_end"):
		_arena.killcam_end()


func is_sniper() -> bool:
	return _def != null and _def.is_sniper()
