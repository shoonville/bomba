extends TestCase

var defs: Array[WeaponDef]
var swap_ticks: int


func setup() -> void:
	var table := TuningLoader.load_file("res://tuning/weapons.json")
	defs = WeaponDef.load_all(table)
	swap_ticks = int(table.get("swap_ticks", 20))


func _fresh() -> Array:
	var states: Array[WeaponLogic.SlotState] = []
	for d in defs:
		var s := WeaponLogic.SlotState.new()
		s.ammo = d.magazine
		states.append(s)
	return [states, WeaponLogic.Shared.new()]


func _inp(fire := false, pressed := false, ads := false, reload := false, weapon := 0) -> WeaponLogic.Inputs:
	var i := WeaponLogic.Inputs.new()
	i.fire = fire
	i.fire_pressed = pressed
	i.ads = ads
	i.reload = reload
	i.weapon = weapon
	return i


func test_loadout() -> void:
	assert_eq(defs.size(), 2)
	assert_eq(defs[0].id, "sniper")
	assert_true(defs[0].is_sniper())
	assert_eq(defs[1].id, "ar")
	assert_true(defs[1].auto)
	assert_eq(defs[1].recoil_pattern_deg.size(), 12)


func test_sniper_bolt_blocks_second_shot() -> void:
	var f := _fresh()
	var out := WeaponLogic.step(defs, f[0], f[1], _inp(true, true), 100, true, swap_ticks)
	assert_true(out.fired)
	assert_eq(f[0][0].ammo, defs[0].magazine - 1)
	var out2 := WeaponLogic.step(defs, f[0], f[1], _inp(true, true), 101, true, swap_ticks)
	assert_false(out2.fired, "inside the bolt cycle")
	var out3 := WeaponLogic.step(defs, f[0], f[1], _inp(true, true), 100 + defs[0].fire_interval_ticks, true, swap_ticks)
	assert_true(out3.fired, "bolt cycled")


func test_sniper_held_trigger_does_not_repeat() -> void:
	var f := _fresh()
	WeaponLogic.step(defs, f[0], f[1], _inp(true, true), 100, true, swap_ticks)
	var out := WeaponLogic.step(defs, f[0], f[1], _inp(true, false), 100 + defs[0].fire_interval_ticks, true, swap_ticks)
	assert_false(out.fired, "semi-auto needs a fresh press")


func test_scope_in_rule_matches_tuning() -> void:
	var f := _fresh()
	var sh: WeaponLogic.Shared = f[1]
	var t := 200
	WeaponLogic.step(defs, f[0], sh, _inp(false, false, true), t, true, swap_ticks)
	assert_eq(sh.ads_since_tick, t)
	# One tick early: hipfire accuracy
	var early := WeaponLogic.step(defs, f[0], sh, _inp(true, true, true), t + defs[0].scope_in_ticks - 1, true, swap_ticks)
	assert_true(early.fired)
	assert_false(early.scoped, "not settled yet")
	assert_near(early.spread_deg, defs[0].hip_spread_deg)
	# Exactly on the settle tick: full accuracy
	var g := _fresh()
	var sh2: WeaponLogic.Shared = g[1]
	WeaponLogic.step(defs, g[0], sh2, _inp(false, false, true), t, true, swap_ticks)
	var on_time := WeaponLogic.step(defs, g[0], sh2, _inp(true, true, true), t + defs[0].scope_in_ticks, true, swap_ticks)
	assert_true(on_time.fired)
	assert_true(on_time.scoped, "quickscope lands exactly at scope_in_ticks")
	assert_near(on_time.spread_deg, 0.0)
	assert_near(WeaponLogic.ads_progress(defs[0], sh2, t + defs[0].scope_in_ticks / 2), 0.5, 1e-6)


func test_ar_auto_fire_rate_and_recoil() -> void:
	var f := _fresh()
	var sh: WeaponLogic.Shared = f[1]
	WeaponLogic.step(defs, f[0], sh, _inp(false, false, false, false, 1), 0, true, swap_ticks)
	assert_eq(sh.slot, 1)
	var t0 := swap_ticks + 1
	var shots := 0
	for t in range(t0, t0 + 60):
		var out := WeaponLogic.step(defs, f[0], sh, _inp(true, false, false, false, 1), t, true, swap_ticks)
		if out.fired:
			shots += 1
	assert_eq(shots, 10, "60 ticks at 6-tick interval = 10 shots")
	assert_eq(f[0][1].ammo, defs[1].magazine - 10)
	assert_eq(f[0][1].recoil_index, 10)
	assert_gt(sh.recoil_pitch, 0.0, "recoil climbed")
	# Idle longer than reset → index resets on next shot
	var t_idle := t0 + 60 + defs[1].recoil_reset_ticks + 5
	var out2 := WeaponLogic.step(defs, f[0], sh, _inp(true, false, false, false, 1), t_idle, true, swap_ticks)
	assert_true(out2.fired)
	assert_eq(f[0][1].recoil_index, 1)


func test_reload_refills_at_end_and_blocks_fire() -> void:
	# The AR: a magazine swap, everything comes back at the end.
	var f := _fresh()
	var sh: WeaponLogic.Shared = f[1]
	sh.slot = 1
	var st: WeaponLogic.SlotState = f[0][1]
	st.ammo = 1
	var out := WeaponLogic.step(defs, f[0], sh, _inp(false, false, false, true, 1), 50, true, swap_ticks)
	assert_true(out.reload_started)
	assert_eq(st.reload_until_tick, 50 + defs[1].reload_ticks)
	var mid := WeaponLogic.step(defs, f[0], sh, _inp(true, true, false, false, 1), 60, true, swap_ticks)
	assert_false(mid.fired, "cannot fire while reloading")
	assert_eq(st.ammo, 1, "nothing comes back early")
	var done := WeaponLogic.step(defs, f[0], sh, _inp(false, false, false, false, 1), 50 + defs[1].reload_ticks, true, swap_ticks)
	assert_true(done.reload_finished)
	assert_eq(st.ammo, defs[1].magazine)


func test_sniper_reloads_one_round_at_a_time() -> void:
	var f := _fresh()
	var sh: WeaponLogic.Shared = f[1]
	var st: WeaponLogic.SlotState = f[0][0]
	var def := defs[0]
	assert_true(def.reload_per_round)
	st.ammo = 0
	var out := WeaponLogic.step(defs, f[0], sh, _inp(false, false, false, true), 100, true, swap_ticks)
	assert_true(out.reload_started)
	var first := 100 + def.reload_start_ticks + def.reload_round_ticks
	assert_eq(st.reload_until_tick, first)
	var rounds := 0
	var finished_at := -1
	for tick in range(101, first + def.reload_round_ticks * def.magazine + 5):
		var o := WeaponLogic.step(defs, f[0], sh, _inp(), tick, true, swap_ticks)
		if o.reload_round:
			rounds += 1
			assert_eq(st.ammo, rounds, "one round per interval at tick %d" % tick)
			assert_eq(tick, first + (rounds - 1) * def.reload_round_ticks, "rounds land every %d ticks" % def.reload_round_ticks)
		if o.reload_finished:
			finished_at = tick
	assert_eq(rounds, def.magazine)
	assert_eq(st.ammo, def.magazine)
	assert_eq(finished_at, first + (def.magazine - 1) * def.reload_round_ticks, "finished as the last round goes in")
	assert_eq(st.reload_until_tick, 0)


func test_sniper_reload_gives_way_to_the_trigger() -> void:
	var f := _fresh()
	var sh: WeaponLogic.Shared = f[1]
	var st: WeaponLogic.SlotState = f[0][0]
	var def := defs[0]
	st.ammo = 0
	WeaponLogic.step(defs, f[0], sh, _inp(false, false, false, true), 100, true, swap_ticks)
	var first := 100 + def.reload_start_ticks + def.reload_round_ticks
	var o := WeaponLogic.step(defs, f[0], sh, _inp(), first, true, swap_ticks)
	assert_true(o.reload_round)
	assert_eq(st.ammo, 1)
	# a tick later the trigger wins: the reload stops and the round fires
	var shot := WeaponLogic.step(defs, f[0], sh, _inp(true, true), first + 1, true, swap_ticks)
	assert_true(shot.fired, "fires the one round that was loaded")
	assert_eq(st.ammo, 0)
	assert_eq(st.reload_until_tick, 0, "reload cancelled by the shot")


func test_empty_mag_auto_reloads() -> void:
	var f := _fresh()
	var st: WeaponLogic.SlotState = f[0][0]
	st.ammo = 0
	var out := WeaponLogic.step(defs, f[0], f[1], _inp(true, true), 10, true, swap_ticks)
	assert_false(out.fired)
	assert_true(out.dry_fire)
	assert_true(out.reload_started)


func test_dead_cannot_fire_or_ads() -> void:
	var f := _fresh()
	var out := WeaponLogic.step(defs, f[0], f[1], _inp(true, true, true), 10, false, swap_ticks)
	assert_false(out.fired)
	assert_false(out.ads_active)


func test_damage_models() -> void:
	var sn := defs[0]
	assert_eq(sn.damage_for(2, 50.0, 1.6), 100)
	assert_eq(sn.damage_for(1, 50.0, 1.0), 100)
	assert_eq(sn.damage_for(1, 50.0, 0.3), sn.damage_legs)
	var ar := defs[1]
	assert_eq(ar.damage_for(1, 5.0, 1.0), ar.damage_near)
	assert_eq(ar.damage_for(1, 100.0, 1.0), ar.damage_far)
	var mid := ar.damage_for(1, (ar.falloff_start_m + ar.falloff_end_m) * 0.5, 1.0)
	assert_eq(mid, int(round((ar.damage_near + ar.damage_far) * 0.5)))
	assert_eq(ar.damage_for(2, 5.0, 1.6), int(round(ar.damage_near * ar.headshot_multiplier)))
	# 100 hp: AR needs 5 near, 9 far; sniper 1. The sniper wins past ~30 m by design.
	assert_eq(int(ceil(100.0 / ar.damage_near)), 5)
	assert_eq(int(ceil(100.0 / ar.damage_far)), 9)


# --- the katana (FIREBALL, 2026-09-24) ---------------------------------------------------------

func _katana() -> Array:
	var table := TuningLoader.load_file("res://tuning/weapons.json")
	var kd := WeaponDef.load_ids(table, ["katana"])
	var states: Array[WeaponLogic.SlotState] = []
	var s := WeaponLogic.SlotState.new()
	s.ammo = kd[0].magazine
	states.append(s)
	return [kd, states, WeaponLogic.Shared.new()]


func test_katana_is_melee_with_no_shot() -> void:
	var k := _katana()
	var kd: Array[WeaponDef] = k[0]
	assert_eq(kd.size(), 1)
	assert_true(kd[0].is_melee())
	assert_false(kd[0].is_sniper())
	var out := WeaponLogic.step(kd, k[1], k[2], _inp(true, true), 100, true, swap_ticks)
	assert_true(out.swung, "the trigger swings")
	assert_false(out.fired, "never a shot")
	assert_eq((k[1] as Array)[0].ammo, kd[0].magazine, "no ammo spent")
	var again := WeaponLogic.step(kd, k[1], k[2], _inp(true, true), 101, true, swap_ticks)
	assert_false(again.swung, "inside the swing")
	var later := WeaponLogic.step(kd, k[1], k[2], _inp(true, true), 100 + kd[0].swing_ticks, true, swap_ticks)
	assert_true(later.swung, "the swing cycled")


func test_katana_parry_window_and_cooldown() -> void:
	var k := _katana()
	var kd: Array[WeaponDef] = k[0]
	var sh: WeaponLogic.Shared = k[2]
	var t := 200
	var out := WeaponLogic.step(kd, k[1], sh, _inp(false, false, true), t, true, swap_ticks)
	assert_true(out.parry_started)
	assert_false(out.ads_active, "the right button is the reflect, not a zoom")
	assert_near(WeaponLogic.ads_progress(kd[0], sh, t + 5), 0.0)
	assert_true(WeaponLogic.parry_active(kd[0], sh, t))
	assert_true(WeaponLogic.parry_active(kd[0], sh, t + kd[0].parry_ticks - 1), "open to the last tick of the window")
	assert_false(WeaponLogic.parry_active(kd[0], sh, t + kd[0].parry_ticks), "closed after it")
	var held := WeaponLogic.step(kd, k[1], sh, _inp(false, false, true), t + 1, true, swap_ticks)
	assert_false(held.parry_started, "holding the button does not re-open it")
	assert_eq(sh.parry_since_tick, t)
	var early := WeaponLogic.step(kd, k[1], sh, _inp(false, false, true), t + kd[0].parry_cooldown_ticks - 1, true, swap_ticks)
	assert_false(early.parry_started, "one tick inside the cooldown")
	var ready := WeaponLogic.step(kd, k[1], sh, _inp(false, false, true), t + kd[0].parry_cooldown_ticks, true, swap_ticks)
	assert_true(ready.parry_started, "the cooldown is the press-to-press wait")
	assert_eq(sh.parry_since_tick, t + kd[0].parry_cooldown_ticks)


func test_katana_dead_or_swapping_cannot_parry() -> void:
	var k := _katana()
	var kd: Array[WeaponDef] = k[0]
	var sh: WeaponLogic.Shared = k[2]
	var dead := WeaponLogic.step(kd, k[1], sh, _inp(false, false, true), 300, false, swap_ticks)
	assert_false(dead.parry_started)
	assert_false(WeaponLogic.parry_active(kd[0], sh, 300))
	sh.swap_until_tick = 320
	var swapping := WeaponLogic.step(kd, k[1], sh, _inp(false, false, true), 310, true, swap_ticks)
	assert_false(swapping.parry_started, "the blade is still coming up")


## The slots node round-trips the parry through its flat state properties (the snapshot the
## match reads left the parry fields out once, 2026-09-24: every bot pressed, no ball reflected).
func test_katana_parry_reads_back_through_the_slots_node() -> void:
	var table := TuningLoader.load_file("res://tuning/weapons.json")
	var kd := WeaponDef.load_ids(table, ["katana"])
	var slots := WeaponSlots.new()
	slots.setup(kd, swap_ticks)
	var input := PlayerInput.new()
	input.ads = true
	var out := slots.step(500, true, input)
	assert_true(out.parry_started)
	assert_eq(slots.parry_since_tick, 500)
	assert_true(slots.parry_active(500), "open on the press tick, read through the node")
	assert_true(slots.parry_active(500 + kd[0].parry_ticks - 1))
	assert_false(slots.parry_active(500 + kd[0].parry_ticks))
	assert_true(slots.parry_progress(509) > 0.0 and slots.parry_progress(509) < 1.0)
	assert_eq(slots.parry_ready_in(510), kd[0].parry_cooldown_ticks - 10)
	input.ads = false
	slots.step(501, true, input)
	assert_true(slots.parry_active(501), "the window stays open after the button is let go")
	input.free()
	slots.free()
