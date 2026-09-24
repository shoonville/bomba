class_name Player
extends CharacterBody3D
## One player's body. Server-authoritative state, rollback-simulated (NETPLAN.md §4-6).
## Movement math lives in MovementModel, weapon math in WeaponLogic, hit tests in
## HitscanResolver; this node wires them into netfox's _rollback_tick.

# --- rollback state (see RollbackSynchronizer config in player.tscn) ---
var health: int = 100
var protected_until_tick: int = 0
var respawn_count: int = 0
var jump_buffer: int = 0
var coyote: int = 0
var last_hit_by: int = 0
var last_hit_info: int = 0  # hit kind * 10 + weapon slot
var head_pitch: float = 0.0
var yaw: float = 0.0
var respawn_tick: int = -1000

# --- plain counters, once per life, kept by the match (FpsMatch._on_player_died and _rpc_kill).
# Not rollback state: a partial resimulation of the death tick re-recorded them from the pre-death
# state and lost kills (2026-09-22).
var kills: int = 0
var deaths: int = 0

# --- identity ---
var peer_id: int = 0
var display_name: String = ""
var colour: Color = Color.WHITE
var is_bot: bool = false
var ctx: PlayerContext
var cfg: MovementConfig
var max_health: int = 100
var lag_comp_max_ticks: int = 15
var respawn_fire_lockout_ticks: int = 12

# --- history and presentation ---
var hitbox_history := HitboxHistory.new()
var snapshot_buffer := SnapshotBuffer.new()
var shots_fired: int = 0
var hits_predicted: int = 0
var hits_landed: int = 0
var correction_snaps: int = 0
var record_trajectory: bool = false
var trajectory: Dictionary = {}

@onready var input: PlayerInput = $Input
@onready var weapons: WeaponSlots = $Weapons
@onready var head: Node3D = $Head
@onready var fire_action: RewindableAction = $FireAction
@onready var rollback_synchronizer: RollbackSynchronizer = $RollbackSynchronizer
@onready var tick_interpolator: TickInterpolator = $TickInterpolator
@onready var collision: CollisionShape3D = $Collision
@onready var visual: Node3D = $Visual

var _acked_respawns: int = 0
var _damage_fx_tick: int = -1
var _pending_damage: Array = []
var _fire_fx: Dictionary = {}
var _fire_fx_tick: int = -1
var _last_predicted_pos: Vector3 = Vector3.ZERO
var _has_predicted_pos: bool = false
var _snap_threshold: float = 0.75
var _remote_recorded_tick: int = -1
var _weapon_event_tick: int = -1
var _was_on_floor: bool = true
var _step_distance: float = 0.0
var _last_step_pos: Vector3 = Vector3.ZERO


func _ready() -> void:
	NetworkTime.before_tick_loop.connect(_before_tick_loop)
	NetworkTime.after_tick_loop.connect(_after_tick_loop)
	# Remote history is read in _after_tick_loop: NetworkRollback has already applied the display
	# state (it runs first on after_tick_loop) and TickInterpolator, which re-applies the previous
	# state to the node, connects deferred and therefore runs after this handler.
	_snap_threshold = Tuning.float_value("net.local_correction_snap_m", 0.75)


## Called by the minigame right after add_child, on every peer, before netfox settles.
func configure(mp: MinigamePlayer, p_ctx: PlayerContext, p_cfg: MovementConfig,
		defs: Array[WeaponDef], swap_ticks: int, p_max_health: int) -> void:
	peer_id = mp.peer_id
	display_name = mp.display_name
	colour = mp.colour
	is_bot = mp.is_bot
	ctx = p_ctx
	cfg = p_cfg
	max_health = p_max_health
	health = p_max_health
	lag_comp_max_ticks = ctx.lag_comp_max_ticks()
	respawn_fire_lockout_ticks = Tuning.int_value("arena.respawn_fire_lockout_ticks", 12)
	var shape := collision.shape as CapsuleShape3D
	shape.radius = cfg.capsule_radius
	shape.height = cfg.capsule_height
	collision.position.y = cfg.capsule_height * 0.5
	head.position.y = cfg.eye_height
	floor_max_angle = deg_to_rad(cfg.max_slope_deg)
	floor_snap_length = cfg.floor_snap_length
	weapons.setup(defs, swap_ticks)
	hitbox_history.capacity = NetworkRollback.history_limit + 16
	var net := Tuning.table("net")
	snapshot_buffer.interp_delay_ticks = float(net.get("remote_interp_delay_ms", 100)) / 1000.0 * NetworkTime.tickrate
	snapshot_buffer.extrapolate_max_ticks = float(net.get("remote_extrapolate_max_ticks", 2))
	snapshot_buffer.snap_distance = float(net.get("remote_snap_distance_m", 2.0))
	# Ownership: body is the server's, input is the player's (server for bots).
	set_multiplayer_authority(1)
	input.set_multiplayer_authority(1 if is_bot else peer_id)
	input.view_tick_source = ctx.remote_render_tick
	rollback_synchronizer.process_settings()
	# The fire action may mutate this body on the server only. On a client, a mutation makes
	# netfox re-record the client's own prediction over authoritative states from the mutated
	# tick onward; when the server disagrees about a predicted shot (typically around a death)
	# the action re-queues that tick every loop and the client can never converge — measured as
	# a ~130-tick outage ending only when the tick fell out of the history window. Remote
	# players' broadcast action state must never mutate a playback node either (it froze them).
	if is_multiplayer_authority():
		fire_action.mutate(self)
	if is_local():
		visual.visible = false


func is_local() -> bool:
	if not is_inside_tree() or multiplayer == null:
		return false
	return not is_bot and peer_id == multiplayer.get_unique_id()


func is_alive() -> bool:
	return health > 0


## True on a client for players it neither owns input for nor has authority over.
func _is_remote_on_client() -> bool:
	return not is_multiplayer_authority() and not input.is_multiplayer_authority()


func eye_position() -> Vector3:
	return global_position + Vector3.UP * cfg.eye_height


func aim_direction(yaw: float, pitch: float) -> Vector3:
	return Vector3(-sin(yaw) * cos(pitch), sin(pitch), -cos(yaw) * cos(pitch)).normalized()


# --- the simulation --------------------------------------------------------------------------

## The game's own share of a tick loop (every player's _rollback_tick, resimulated ticks
## included), for the soak report against netfox's loop time. Reset by the recorder each loop.
static var sim_us_this_loop: int = 0
static var sim_node_ticks_this_loop: int = 0

## The last REPLAY_TICKS ticks of this body as this peer saw them, for the final-kill cam: per
## tick x, y, z, yaw, head pitch, health, weapon slot and the tick itself, one entry per tick
## loop (a loop that ran several ticks records only its last; replay_sample steps back to the
## nearest recorded tick).
const REPLAY_TICKS := 300
const REPLAY_STRIDE := 9   # ... and the scope-in progress (the kill cam scopes when the killer did)
var _replay := PackedFloat32Array()


func _record_replay(tick: int) -> void:
	if _replay.is_empty():
		_replay.resize(REPLAY_TICKS * REPLAY_STRIDE)
		_replay.fill(-1.0)
	var i := posmod(tick, REPLAY_TICKS) * REPLAY_STRIDE
	_replay[i] = global_position.x
	_replay[i + 1] = global_position.y
	_replay[i + 2] = global_position.z
	_replay[i + 3] = yaw
	_replay[i + 4] = head_pitch
	_replay[i + 5] = float(health)
	_replay[i + 6] = float(weapons.slot)
	_replay[i + 7] = float(tick)
	_replay[i + 8] = weapons.ads_progress(tick)


func _replay_at(tick: int) -> Dictionary:
	if _replay.is_empty():
		return {}
	for back in 8:
		var tk := tick - back
		var i := posmod(tk, REPLAY_TICKS) * REPLAY_STRIDE
		if int(_replay[i + 7]) == tk:
			return {"pos": Vector3(_replay[i], _replay[i + 1], _replay[i + 2]), "yaw": _replay[i + 3],
				"pitch": _replay[i + 4], "health": int(_replay[i + 5]), "slot": int(_replay[i + 6]),
				"ads": _replay[i + 8]}
	return {}


## The body's pose at a (fractional) tick, interpolated between recorded ticks; {} when the
## buffer does not reach it.
func replay_sample(t: float) -> Dictionary:
	var t0 := int(floor(t))
	var a := _replay_at(t0)
	if a.is_empty():
		return {}
	var b := _replay_at(t0 + 1)
	if b.is_empty():
		return a
	var f := t - float(t0)
	return {"pos": (a["pos"] as Vector3).lerp(b["pos"], f), "yaw": lerp_angle(a["yaw"], b["yaw"], f),
		"pitch": lerpf(a["pitch"], b["pitch"], f), "health": a["health"], "slot": a["slot"],
		"ads": lerpf(a["ads"], b["ads"], f)}


func _rollback_tick(delta: float, tick: int, is_fresh: bool) -> void:
	var t0 := Time.get_ticks_usec()
	_rollback_tick_body(delta, tick, is_fresh)
	sim_us_this_loop += Time.get_ticks_usec() - t0
	sim_node_ticks_this_loop += 1


func _rollback_tick_body(delta: float, tick: int, _is_fresh: bool) -> void:
	if _is_remote_on_client():
		# Only reached when mutated (took predicted damage). Never move a remote player, and never
		# write its hitbox history from here: that history comes from received state only.
		return
	var alive := health > 0

	# Look: absolute angles from input (NETPLAN §4). yaw/pitch are the replicated state; the
	# node's rotation is derived from them (a Transform3D would cost 52 bytes a tick).
	yaw = wrapf(input.yaw, -PI, PI)
	rotation = Vector3(0.0, yaw, 0.0)
	head_pitch = clampf(input.pitch, -deg_to_rad(cfg.pitch_limit_deg), deg_to_rad(cfg.pitch_limit_deg))
	head.rotation.x = head_pitch

	# Movement (MovementModel is pure; move_and_slide applies it). Frozen ticks (the round over,
	# the briefing before it starts) take no movement input: a tick-based rule from replicated
	# state, so every peer freezes on the same tick.
	var frozen := ctx != null and ctx.is_frozen(tick)
	if alive:
		_force_update_is_on_floor()
		var r := MovementModel.step(velocity, is_on_floor(), Vector2.ZERO if frozen else input.move, rotation.y,
			input.jump and not frozen, jump_buffer, coyote, delta, cfg)
		velocity = r.velocity
		jump_buffer = r.jump_buffer
		coyote = r.coyote
		velocity *= NetworkTime.physics_factor
		move_and_slide()
		velocity /= NetworkTime.physics_factor
	else:
		velocity = Vector3.ZERO

	# Weapons. Inputs queued before the player learned of a death do not fire the fresh body.
	var recoil_before := Vector2(weapons.recoil_yaw, weapons.recoil_pitch)
	var can_use_weapons := alive and not frozen and tick >= respawn_tick + respawn_fire_lockout_ticks \
		and (ctx == null or ctx.can_fire_at(tick))
	var out := weapons.step(tick, can_use_weapons, input)
	var predicting := rollback_synchronizer.is_predicting()
	if not predicting:
		fire_action.set_active(out.fired)
		match fire_action.get_status():
			RewindableAction.CONFIRMING, RewindableAction.ACTIVE:
				_resolve_shot(tick, out, recoil_before)
			RewindableAction.CANCELLING:
				fire_action.erase_context()
	if out.fired and Tuning.value("arena.spawn_protection_ends_on_fire", true) and protected_until_tick > tick:
		protected_until_tick = tick

	# Death: authority only (NETPLAN §6.3).
	if is_multiplayer_authority() and health <= 0 and ctx != null:
		ctx.on_player_died(self, tick)

	# netfox convention: simulating tick T produces state T+1. Hitboxes and the trajectory log
	# use state ticks so they line up with what remote peers receive and record.
	_record_hitboxes(tick + 1)
	if record_trajectory:
		trajectory[tick + 1] = [global_position, health, kills, deaths, yaw]


func _force_update_is_on_floor() -> void:
	var old_velocity := velocity
	velocity = Vector3.ZERO
	move_and_slide()
	velocity = old_velocity


func _record_hitboxes(tick: int) -> void:
	hitbox_history.record(tick, Hitboxes.sample_from(global_position, cfg, health > 0))


func _resolve_shot(tick: int, out: WeaponLogic.Outcome, recoil_before: Vector2) -> void:
	var def := weapons.current_def()
	if def == null or ctx == null:
		return
	var origin := eye_position()
	var dir := aim_direction(rotation.y, head_pitch)
	dir = HitscanMath.offset_direction(dir, recoil_before.x, recoil_before.y)
	if out.spread_deg > 0.0:
		var spread := HitscanMath.spread_offset(Rng.tick_stream("spread", tick, peer_id), out.spread_deg)
		dir = HitscanMath.offset_direction(dir, spread.x, spread.y)
	var view_tick := clampf(input.view_tick, float(tick - lag_comp_max_ticks), float(tick))
	var res := HitscanResolver.resolve(ctx.space_state(), origin, dir, def.range_m, view_tick,
		ctx.targets_for(self), ctx.world_mask())
	var first_time := not fire_action.has_context()
	if first_time:
		fire_action.set_context(true)
		shots_fired += 1
		Log.debug("shot", "SHOT peer=%d tick=%d kind=%s victim=%d dist=%.2f view=%.2f o=%.3f,%.3f,%.3f d=%.4f,%.4f,%.4f hh=%.2f" % [
			peer_id, tick, HitscanResolver.kind_name(res.kind), res.target_id, res.distance, view_tick,
			origin.x, origin.y, origin.z, dir.x, dir.y, dir.z, res.hit_height])
	if res.kind == HitscanResolver.BODY or res.kind == HitscanResolver.HEAD:
		var victim := res.target as Player
		if victim != null:
			var dmg := def.damage_for(res.kind, res.distance, res.hit_height)
			var landed := victim.take_damage(dmg, peer_id, tick, res.kind, weapons.slot)
			if landed and first_time:
				if is_multiplayer_authority():
					hits_landed += 1
				else:
					hits_predicted += 1
			if not landed:
				res.kind = HitscanResolver.WORLD
	if fire_action.get_status() == RewindableAction.CONFIRMING and tick > _fire_fx_tick:
		_fire_fx = {"tick": tick, "origin": origin, "point": res.point, "kind": res.kind,
			"victim": res.target_id, "weapon": def.id, "scoped": out.scoped, "view_tick": view_tick}
	if is_multiplayer_authority():
		ctx.notify_shot(self, tick, origin, res.point, res.kind)


## Returns true if the damage counted. Predicted on the shooter's client, authoritative on the
## server; both mark the victim mutated so the change is recorded and resimulated.
func take_damage(amount: int, from_id: int, tick: int, kind: int, weapon_slot: int) -> bool:
	if health <= 0:
		return false
	if tick < protected_until_tick:
		return false
	health -= amount
	last_hit_by = from_id
	last_hit_info = kind * 10 + weapon_slot
	if is_multiplayer_authority():
		# Server: record the change and resimulate the victim from this tick (a late hit must
		# stick and a death must be detected). Clients never mutate a remote victim: netfox would
		# record the victim's stale state under the current tick and shadow every newer received
		# state, freezing the victim on screen for as long as the shooter keeps hitting it.
		NetworkRollback.mutate(self)
	if is_local() and tick > _damage_fx_tick:
		_pending_damage.append({"tick": tick, "amount": amount, "from": from_id})
	return true


## Authority: teleport to a spawn and restore. Called by the minigame from on_player_died.
func respawn_at(spawn_position: Vector3, spawn_yaw: float, tick: int, protection_ticks: int) -> void:
	global_position = spawn_position
	yaw = spawn_yaw
	rotation = Vector3(0.0, spawn_yaw, 0.0)
	velocity = Vector3.ZERO
	health = max_health
	protected_until_tick = tick + protection_ticks
	respawn_count += 1
	respawn_tick = tick
	last_hit_by = 0
	last_hit_info = 0
	jump_buffer = 0
	coyote = 0
	weapons.refill()   # full magazines on a fresh life (Sean, 2026-09-23)
	if input.is_multiplayer_authority():
		input.set_look(spawn_yaw, 0.0)


# --- presentation hooks ----------------------------------------------------------------------

func _before_tick_loop() -> void:
	if not is_inside_tree():
		return
	_acked_respawns = respawn_count
	if is_local() and not is_multiplayer_authority():
		_last_predicted_pos = global_position
		_has_predicted_pos = true


func _after_tick_loop() -> void:
	if not is_inside_tree():
		return
	_record_replay(NetworkTime.tick)
	if respawn_count != _acked_respawns:
		tick_interpolator.teleport()
		_acked_respawns = respawn_count
		if is_local():
			input.set_look(rotation.y, 0.0)
			Events.local_respawned.emit()
	if is_local():
		if _has_predicted_pos and (global_position - _last_predicted_pos).length() > _snap_threshold \
				and respawn_count == _acked_respawns:
			correction_snaps += 1
			tick_interpolator.teleport()
		if fire_action.has_confirmed() and not _fire_fx.is_empty() and int(_fire_fx["tick"]) > _fire_fx_tick:
			_fire_fx_tick = int(_fire_fx["tick"])
			Events.local_fired.emit(str(_fire_fx["weapon"]))
			var k := int(_fire_fx["kind"])
			Events.local_shot_fx.emit(_fire_fx["origin"], _fire_fx["point"], k)
			if k == HitscanResolver.BODY or k == HitscanResolver.HEAD:
				Events.local_hit_predicted.emit(k, int(_fire_fx["victim"]))
		for d in _pending_damage:
			if int(d["tick"]) > _damage_fx_tick:
				_damage_fx_tick = int(d["tick"])
				Events.local_damaged.emit(int(d["amount"]), int(d["from"]))
		_pending_damage.clear()
		_emit_weapon_events()
		_emit_movement_events()
	elif _is_remote_on_client():
		_record_remote_state()


func _record_remote_state() -> void:
	rotation = Vector3(0.0, yaw, 0.0)
	head.rotation.x = head_pitch
	var t := rollback_synchronizer.get_last_known_state()
	if t > _remote_recorded_tick:
		_remote_recorded_tick = t
		hitbox_history.record(t, Hitboxes.sample_from(global_position, cfg, health > 0))
		snapshot_buffer.push(t, global_position, yaw, head_pitch)


func _emit_weapon_events() -> void:
	var out := weapons.last_outcome
	var t := weapons.last_outcome_tick
	if t <= _weapon_event_tick:
		return
	_weapon_event_tick = t
	if out.reload_started:
		Events.local_weapon_event.emit("reload_started")
	if out.reload_round:
		Events.local_weapon_event.emit("reload_round")
	if out.reload_finished:
		Events.local_weapon_event.emit("reload_finished")
	if out.dry_fire:
		Events.local_weapon_event.emit("dry_fire")
	if out.swapped:
		Events.local_weapon_event.emit("swapped")
		Events.local_weapon_changed.emit(out.weapon_id)


func _emit_movement_events() -> void:
	var on_floor := is_on_floor()
	if health > 0:
		if _was_on_floor and not on_floor and velocity.y > 1.0:
			Events.local_jump.emit()
		elif not _was_on_floor and on_floor:
			Events.local_land.emit()
			_step_distance = 0.0
		if on_floor:
			var moved := (global_position - _last_step_pos)
			moved.y = 0.0
			_step_distance += moved.length()
			if _step_distance >= 2.1 and Vector2(velocity.x, velocity.z).length() > 1.0:
				_step_distance = 0.0
				Events.local_footstep.emit()
	_was_on_floor = on_floor
	_last_step_pos = global_position


func get_fire_fx() -> Dictionary:
	return _fire_fx
