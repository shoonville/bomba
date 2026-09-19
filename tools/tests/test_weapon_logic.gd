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
	var f := _fresh()
	var sh: WeaponLogic.Shared = f[1]
	var st: WeaponLogic.SlotState = f[0][0]
	st.ammo = 1
	var out := WeaponLogic.step(defs, f[0], sh, _inp(false, false, false, true), 50, true, swap_ticks)
	assert_true(out.reload_started)
	assert_eq(st.reload_until_tick, 50 + defs[0].reload_ticks)
	var mid := WeaponLogic.step(defs, f[0], sh, _inp(true, true), 60, true, swap_ticks)
	assert_false(mid.fired, "cannot fire while reloading")
	var done := WeaponLogic.step(defs, f[0], sh, _inp(), 50 + defs[0].reload_ticks, true, swap_ticks)
	assert_true(done.reload_finished)
	assert_eq(st.ammo, defs[0].magazine)


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
