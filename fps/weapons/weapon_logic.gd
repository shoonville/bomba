class_name WeaponLogic
extends RefCounted
## Pure weapon state machine. Runs identically on server and client inside _rollback_tick.
## The node owning the flat state properties copies them into these small state objects,
## calls step(), and copies them back. Nothing here touches nodes, RNG or the scene.


class SlotState:
	var ammo: int = 0
	var next_fire_tick: int = 0
	var reload_until_tick: int = 0  # 0 = not reloading
	var recoil_index: int = 0
	var last_shot_tick: int = -1000


class Shared:
	var slot: int = 0
	var swap_until_tick: int = 0
	var ads_since_tick: int = -1  # -1 = hip
	var recoil_pitch: float = 0.0
	var recoil_yaw: float = 0.0


class Inputs:
	var fire: bool = false          # held
	var fire_pressed: bool = false  # one-off edge, at most one tick per press
	var ads: bool = false
	var reload: bool = false
	var weapon: int = 0


class Outcome:
	var fired: bool = false
	var weapon_id: String = ""
	var spread_deg: float = 0.0
	var scoped: bool = false        # sniper fully settled at the moment of the shot
	var ads_active: bool = false
	var swapped: bool = false
	var reload_started: bool = false
	var reload_finished: bool = false
	var reload_round: bool = false   # one round went in (per-round reloads)
	var dry_fire: bool = false


static func can_fire(def: WeaponDef, st: SlotState, sh: Shared, tick: int, alive: bool) -> bool:
	if not alive:
		return false
	if tick < st.next_fire_tick:
		return false
	if st.ammo <= 0:
		return false
	if st.reload_until_tick > 0:
		return false
	if tick < sh.swap_until_tick:
		return false
	return true


static func is_scoped(def: WeaponDef, sh: Shared, tick: int) -> bool:
	return sh.ads_since_tick >= 0 and (tick - sh.ads_since_tick) >= def.scope_in_ticks


## ADS progress 0..1 for animation and FOV; sniper uses scope_in_ticks, AR uses ads_in_ticks.
static func ads_progress(def: WeaponDef, sh: Shared, tick: int) -> float:
	if sh.ads_since_tick < 0:
		return 0.0
	var dur := def.scope_in_ticks if def.is_sniper() else def.ads_in_ticks
	if dur <= 0:
		return 1.0
	return clampf(float(tick - sh.ads_since_tick) / float(dur), 0.0, 1.0)


static func step(defs: Array[WeaponDef], states: Array[SlotState], sh: Shared, inp: Inputs,
		tick: int, alive: bool, swap_ticks: int) -> Outcome:
	var out := Outcome.new()
	if defs.is_empty():
		return out

	# 1. Weapon swap request
	var want := clampi(inp.weapon, 0, defs.size() - 1)
	if alive and want != sh.slot and tick >= sh.swap_until_tick:
		sh.slot = want
		sh.swap_until_tick = tick + swap_ticks
		sh.ads_since_tick = -1
		out.swapped = true
	var def := defs[sh.slot]
	var st := states[sh.slot]
	out.weapon_id = def.id

	# 2. Reload progress (derived from state, so it is rollback-safe). A per-round weapon loads
	# one round each interval until full; anything else refills at the end.
	if st.reload_until_tick > 0 and tick >= st.reload_until_tick:
		if def.reload_per_round:
			st.ammo = mini(def.magazine, st.ammo + 1)
			out.reload_round = true
			if st.ammo >= def.magazine:
				st.reload_until_tick = 0
				out.reload_finished = true
			else:
				st.reload_until_tick = tick + def.reload_round_ticks
		else:
			st.ammo = def.magazine
			st.reload_until_tick = 0
			out.reload_finished = true

	# 3. ADS
	var swapping := tick < sh.swap_until_tick
	var reloading := st.reload_until_tick > 0
	if alive and inp.ads and not swapping and not reloading:
		if sh.ads_since_tick < 0:
			sh.ads_since_tick = tick
	else:
		sh.ads_since_tick = -1
	out.ads_active = sh.ads_since_tick >= 0

	# 4. Reload start (explicit, or automatic on an empty trigger pull)
	var trigger := inp.fire if def.auto else inp.fire_pressed
	if alive and not reloading and not swapping and tick >= st.next_fire_tick and st.ammo < def.magazine:
		if inp.reload or (trigger and st.ammo <= 0):
			st.reload_until_tick = tick + (def.reload_start_ticks + def.reload_round_ticks if def.reload_per_round else def.reload_ticks)
			sh.ads_since_tick = -1
			out.ads_active = false
			out.reload_started = true
			reloading = true
			if trigger and st.ammo <= 0:
				out.dry_fire = true

	# 5. Fire. A per-round reload with something in the chamber gives way to the trigger.
	if trigger and def.reload_per_round and st.reload_until_tick > 0 and st.ammo > 0 and alive and tick >= st.next_fire_tick and not swapping:
		st.reload_until_tick = 0
		out.reload_finished = true
	if trigger and can_fire(def, st, sh, tick, alive):
		out.fired = true
		st.ammo -= 1
		st.next_fire_tick = tick + def.fire_interval_ticks
		if def.is_sniper():
			out.scoped = is_scoped(def, sh, tick)
			out.spread_deg = def.ads_spread_deg if out.scoped else def.hip_spread_deg
			sh.recoil_pitch += def.recoil_kick_deg
			st.recoil_index += 1
		else:
			if tick - st.last_shot_tick > def.recoil_reset_ticks:
				st.recoil_index = 0
			var n := def.recoil_pattern_deg.size()
			if n > 0:
				var kick := def.recoil_pattern_deg[mini(st.recoil_index, n - 1)]
				if out.ads_active:
					kick *= def.ads_recoil_multiplier
				sh.recoil_yaw += kick.x
				sh.recoil_pitch += kick.y
			st.recoil_index += 1
			out.spread_deg = def.spread_deg
		st.last_shot_tick = tick

	# 6. Recoil recovery: none while a burst is live, then a fixed rate per tick
	if tick - st.last_shot_tick > def.recoil_recovery_delay_ticks:
		var rec := def.recoil_recovery_per_tick_deg
		sh.recoil_pitch = move_toward(sh.recoil_pitch, 0.0, rec)
		sh.recoil_yaw = move_toward(sh.recoil_yaw, 0.0, rec)
	return out
