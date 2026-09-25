class_name WeaponSlots
extends Node
## Holds the flat weapon state properties (rollback state, NETPLAN.md §4) and runs WeaponLogic.
## Three slots are declared so a third weapon (melee, later) needs no new properties.

const MAX_SLOTS := 3

var slot: int = 0
var swap_until_tick: int = 0
var ads_since_tick: int = -1
var recoil_pitch: float = 0.0
var recoil_yaw: float = 0.0
var parry_since_tick: int = -1   # the katana's reflect window (WeaponLogic.parry_active)
var parry_ready_tick: int = 0

var w0_ammo: int = 0
var w0_next_fire_tick: int = 0
var w0_reload_until_tick: int = 0
var w0_recoil_index: int = 0
var w0_last_shot_tick: int = -1000
var w1_ammo: int = 0
var w1_next_fire_tick: int = 0
var w1_reload_until_tick: int = 0
var w1_recoil_index: int = 0
var w1_last_shot_tick: int = -1000
var w2_ammo: int = 0
var w2_next_fire_tick: int = 0
var w2_reload_until_tick: int = 0
var w2_recoil_index: int = 0
var w2_last_shot_tick: int = -1000

var defs: Array[WeaponDef] = []
var swap_ticks: int = 20
var last_outcome: WeaponLogic.Outcome = WeaponLogic.Outcome.new()
var last_outcome_tick: int = -1

var _states: Array[WeaponLogic.SlotState] = []
var _shared := WeaponLogic.Shared.new()


static func state_property_paths(node_name: String) -> Array[String]:
	var out: Array[String] = []
	for p in ["slot", "swap_until_tick", "ads_since_tick", "recoil_pitch", "recoil_yaw", "parry_since_tick", "parry_ready_tick"]:
		out.append("%s:%s" % [node_name, p])
	for i in MAX_SLOTS:
		for p in ["ammo", "next_fire_tick", "reload_until_tick", "recoil_index", "last_shot_tick"]:
			out.append("%s:w%d_%s" % [node_name, i, p])
	return out


func setup(p_defs: Array[WeaponDef], p_swap_ticks: int) -> void:
	defs = p_defs
	swap_ticks = p_swap_ticks
	_states.clear()
	for i in MAX_SLOTS:
		_states.append(WeaponLogic.SlotState.new())
	for i in defs.size():
		set("w%d_ammo" % i, defs[i].magazine)
		set("w%d_next_fire_tick" % i, 0)
		set("w%d_reload_until_tick" % i, 0)
		set("w%d_recoil_index" % i, 0)
		set("w%d_last_shot_tick" % i, -1000)


## A fresh life: every slot full, nothing reloading or cooling down (Sean, 2026-09-23: respawn
## with full ammo). Authority-side, inside the tick, with the rest of the respawn.
func refill() -> void:
	for i in defs.size():
		set("w%d_ammo" % i, defs[i].magazine)
		set("w%d_reload_until_tick" % i, 0)
		set("w%d_next_fire_tick" % i, 0)


func current_def() -> WeaponDef:
	if defs.is_empty():
		return null
	return defs[clampi(slot, 0, defs.size() - 1)]


func def_for_slot(i: int) -> WeaponDef:
	if i < 0 or i >= defs.size():
		return null
	return defs[i]


func ammo_for_slot(i: int) -> int:
	return int(get("w%d_ammo" % i))


func is_reloading() -> bool:
	return int(get("w%d_reload_until_tick" % slot)) > 0


func shared_snapshot() -> WeaponLogic.Shared:
	var sh := WeaponLogic.Shared.new()
	sh.slot = slot
	sh.swap_until_tick = swap_until_tick
	sh.ads_since_tick = ads_since_tick
	sh.recoil_pitch = recoil_pitch
	sh.recoil_yaw = recoil_yaw
	sh.parry_since_tick = parry_since_tick
	sh.parry_ready_tick = parry_ready_tick
	return sh


func ads_progress(tick: int) -> float:
	var d := current_def()
	if d == null:
		return 0.0
	return WeaponLogic.ads_progress(d, shared_snapshot(), tick)


func is_scoped(tick: int) -> bool:
	var d := current_def()
	if d == null or not d.is_sniper():
		return false
	return WeaponLogic.is_scoped(d, shared_snapshot(), tick)


## The katana's reflect window is open on this tick.
func parry_active(tick: int) -> bool:
	var d := current_def()
	if d == null:
		return false
	return WeaponLogic.parry_active(d, shared_snapshot(), tick)


## 0..1 through the reflect window (the blade's guard animation); 0 when it is closed.
func parry_progress(tick: int) -> float:
	var d := current_def()
	if d == null or not d.is_melee() or parry_since_tick < 0 or d.parry_ticks <= 0:
		return 0.0
	var k := float(tick - parry_since_tick) / float(d.parry_ticks)
	return clampf(k, 0.0, 1.0) if k < 1.0 else 0.0


## Ticks until the next reflect press counts; 0 when ready.
func parry_ready_in(tick: int) -> int:
	return maxi(0, parry_ready_tick - tick)


## Run one tick of weapon logic from the input. Returns the outcome; the player resolves shots.
func step(tick: int, alive: bool, input: PlayerInput) -> WeaponLogic.Outcome:
	if defs.is_empty():
		return WeaponLogic.Outcome.new()
	_load()
	var inp := WeaponLogic.Inputs.new()
	inp.fire = input.fire
	inp.fire_pressed = input.fire_pressed
	inp.ads = input.ads
	inp.reload = input.reload
	inp.weapon = input.weapon
	last_outcome = WeaponLogic.step(defs, _states, _shared, inp, tick, alive, swap_ticks)
	last_outcome_tick = tick
	_store()
	return last_outcome


func _load() -> void:
	_shared.slot = slot
	_shared.swap_until_tick = swap_until_tick
	_shared.ads_since_tick = ads_since_tick
	_shared.recoil_pitch = recoil_pitch
	_shared.recoil_yaw = recoil_yaw
	_shared.parry_since_tick = parry_since_tick
	_shared.parry_ready_tick = parry_ready_tick
	for i in defs.size():
		var s := _states[i]
		s.ammo = int(get("w%d_ammo" % i))
		s.next_fire_tick = int(get("w%d_next_fire_tick" % i))
		s.reload_until_tick = int(get("w%d_reload_until_tick" % i))
		s.recoil_index = int(get("w%d_recoil_index" % i))
		s.last_shot_tick = int(get("w%d_last_shot_tick" % i))


func _store() -> void:
	slot = _shared.slot
	swap_until_tick = _shared.swap_until_tick
	ads_since_tick = _shared.ads_since_tick
	recoil_pitch = _shared.recoil_pitch
	recoil_yaw = _shared.recoil_yaw
	parry_since_tick = _shared.parry_since_tick
	parry_ready_tick = _shared.parry_ready_tick
	for i in defs.size():
		var s := _states[i]
		set("w%d_ammo" % i, s.ammo)
		set("w%d_next_fire_tick" % i, s.next_fire_tick)
		set("w%d_reload_until_tick" % i, s.reload_until_tick)
		set("w%d_recoil_index" % i, s.recoil_index)
		set("w%d_last_shot_tick" % i, s.last_shot_tick)
