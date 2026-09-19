class_name PlayerInput
extends Node
## The input properties of one player (NETPLAN.md §4). Owned by the player's peer, or by the
## server for bots. Gathered once per tick loop; edges are buffered so a press between two
## ticks is never lost, and held inputs are true if they were held at any frame since the
## last gather.

var move: Vector2 = Vector2.ZERO
var yaw: float = 0.0
var pitch: float = 0.0
var jump: bool = false
var fire: bool = false
var fire_pressed: bool = false
var ads: bool = false
var reload: bool = false
var weapon: int = 0
var view_tick: float = 0.0

var brain: Node = null
var view_tick_source: Callable
var ads_hint: bool = false

# Raw look accumulators; the camera rig reads these every frame for zero-lag mouse look.
var look_yaw: float = 0.0
var look_pitch: float = 0.0

var mouse_sensitivity: float = 0.0022
var ads_sensitivity_multiplier: float = 0.6
var invert_y: bool = false
var pitch_limit: float = deg_to_rad(89.0)
var enabled: bool = true

var _move_accum: Vector2 = Vector2.ZERO
var _move_samples: int = 0
var _jump_edge: bool = false
var _fire_edge: bool = false
var _reload_edge: bool = false
var _fire_any: bool = false
var _ads_any: bool = false
var _weapon_request: int = 0
var _gathers: int = 0


func _ready() -> void:
	var controls := Tuning.table("controls")
	mouse_sensitivity = float(controls.get("mouse_sensitivity", mouse_sensitivity))
	ads_sensitivity_multiplier = float(controls.get("ads_sensitivity_multiplier", ads_sensitivity_multiplier))
	invert_y = bool(controls.get("invert_y", invert_y))
	NetworkTime.before_tick_loop.connect(_on_before_tick_loop)


func is_local_human() -> bool:
	return brain == null and is_multiplayer_authority()


func set_look(p_yaw: float, p_pitch: float) -> void:
	look_yaw = wrapf(p_yaw, -PI, PI)
	look_pitch = clampf(p_pitch, -pitch_limit, pitch_limit)
	yaw = look_yaw
	pitch = look_pitch


func _input(event: InputEvent) -> void:
	if not enabled or not is_local_human():
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var sens := mouse_sensitivity * (ads_sensitivity_multiplier if ads_hint else 1.0)
		var rel: Vector2 = event.relative
		look_yaw = wrapf(look_yaw - rel.x * sens, -PI, PI)
		var dy := rel.y * sens * (-1.0 if invert_y else 1.0)
		look_pitch = clampf(look_pitch - dy, -pitch_limit, pitch_limit)


func _process(_delta: float) -> void:
	if not enabled or not is_local_human():
		return
	_move_accum += Input.get_vector("move_left", "move_right", "move_back", "move_forward")
	_move_samples += 1
	if Input.is_action_just_pressed("jump"):
		_jump_edge = true
	if Input.is_action_just_pressed("fire"):
		_fire_edge = true
	if Input.is_action_pressed("fire"):
		_fire_any = true
	if Input.is_action_pressed("ads"):
		_ads_any = true
	if Input.is_action_just_pressed("reload"):
		_reload_edge = true
	if Input.is_action_just_pressed("weapon_1"):
		_weapon_request = 0
	if Input.is_action_just_pressed("weapon_2"):
		_weapon_request = 1
	if Input.is_action_just_pressed("weapon_swap"):
		_weapon_request = 1 - _weapon_request


func _on_before_tick_loop() -> void:
	if not is_inside_tree() or not is_multiplayer_authority():
		return
	_gathers += 1
	if brain != null and brain.has_method("gather_into"):
		brain.gather_into(self)
	elif enabled:
		_gather_human()
	else:
		move = Vector2.ZERO
		jump = false
		fire = false
		fire_pressed = false
		ads = false
		reload = false
	if view_tick_source.is_valid():
		view_tick = float(view_tick_source.call())
	else:
		view_tick = float(NetworkTime.tick)


func _gather_human() -> void:
	if _move_samples > 0:
		move = _move_accum / float(_move_samples)
	else:
		move = Input.get_vector("move_left", "move_right", "move_back", "move_forward")
	if move.length_squared() > 1.0:
		move = move.normalized()
	yaw = look_yaw
	pitch = look_pitch
	jump = _jump_edge
	fire = _fire_any or Input.is_action_pressed("fire")
	fire_pressed = _fire_edge
	ads = _ads_any or Input.is_action_pressed("ads") or Game.args.has("force_ads")
	reload = _reload_edge
	weapon = int(Game.args.get("force_weapon", _weapon_request))
	_move_accum = Vector2.ZERO
	_move_samples = 0
	_jump_edge = false
	_fire_edge = false
	_reload_edge = false
	_fire_any = false
	_ads_any = false
