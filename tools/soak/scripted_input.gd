class_name ScriptedInputDriver
extends Node
## Feeds a seeded, per-tick input sequence into a PlayerInput from NetworkTime.before_tick, so
## the recorded input for tick N is a pure function of (seed, peer, N) whatever the frame rate.
## This is the input source for the determinism harness (NETPLAN.md §3).

var input: PlayerInput
var seed_value: int = 0
var peer: int = 0
var segment_ticks: int = 30


func setup(p_input: PlayerInput, p_seed: int, p_peer: int) -> void:
	input = p_input
	seed_value = p_seed
	peer = p_peer
	input.enabled = false


func _ready() -> void:
	NetworkTime.before_tick.connect(_before_tick)


func _before_tick(_delta: float, tick: int) -> void:
	if input == null or not input.is_multiplayer_authority():
		return
	var seg := tick / segment_ticks
	var rs := SeededRng.make_tick(seed_value, "scripted_seg", seg, peer)
	var r := SeededRng.make_tick(seed_value, "scripted", tick, peer)
	var move := Vector2(rs.randf_range(-1.0, 1.0), rs.randf_range(-1.0, 1.0)).limit_length(1.0)
	var base_yaw := rs.randf_range(-PI, PI)
	var yaw_rate := rs.randf_range(-0.03, 0.03)
	var pitch := rs.randf_range(-0.5, 0.5)
	input.move = move
	input.yaw = wrapf(base_yaw + yaw_rate * float(tick % segment_ticks), -PI, PI)
	input.pitch = pitch
	input.look_yaw = input.yaw
	input.look_pitch = input.pitch
	input.jump = r.randf() < 0.03
	input.fire = r.randf() < 0.35
	input.fire_pressed = r.randf() < 0.06
	input.ads = rs.randf() < 0.4
	input.reload = r.randf() < 0.01
	input.weapon = 0 if rs.randf() < 0.5 else 1
	input.view_tick = float(tick)
