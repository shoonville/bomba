class_name WeaponDef
extends RefCounted
## Typed view of one entry in tuning/weapons.json. Two damage models: "flat" (sniper: head/body/
## legs) and "falloff" (AR: linear near→far by distance, headshot multiplier).

var id: String = ""
var display_name: String = ""
var auto: bool = false
var fire_interval_ticks: int = 10
var magazine: int = 1
var reload_ticks: int = 60
var range_m: float = 100.0
var ads_fov_vertical: float = 40.0
var recoil_recovery_per_tick_deg: float = 0.1
var recoil_recovery_delay_ticks: int = 4
var model: String = "flat"

# flat model
var damage_body: int = 100
var damage_head: int = 100
var damage_legs: int = 70
var legs_below_height: float = 0.75
var scope_in_ticks: int = 16
var hip_spread_deg: float = 3.5
var ads_spread_deg: float = 0.0
var recoil_kick_deg: float = 3.0

# falloff model
var damage_near: int = 20
var damage_far: int = 10
var headshot_multiplier: float = 1.4
var falloff_start_m: float = 12.0
var falloff_end_m: float = 38.0
var ads_in_ticks: int = 8
var spread_deg: float = 0.0
var ads_recoil_multiplier: float = 0.7
var recoil_reset_ticks: int = 14
var recoil_pattern_deg: Array[Vector2] = []


static func from_dict(p_id: String, d: Dictionary) -> WeaponDef:
	var w := WeaponDef.new()
	w.id = p_id
	w.display_name = str(d.get("display_name", p_id.to_upper()))
	w.auto = bool(d.get("auto", false))
	w.fire_interval_ticks = int(d.get("fire_interval_ticks", w.fire_interval_ticks))
	w.magazine = int(d.get("magazine", w.magazine))
	w.reload_ticks = int(d.get("reload_ticks", w.reload_ticks))
	w.range_m = float(d.get("range_m", w.range_m))
	w.ads_fov_vertical = float(d.get("ads_fov_vertical", w.ads_fov_vertical))
	w.recoil_recovery_per_tick_deg = float(d.get("recoil_recovery_per_tick_deg", w.recoil_recovery_per_tick_deg))
	w.recoil_recovery_delay_ticks = int(d.get("recoil_recovery_delay_ticks", w.recoil_recovery_delay_ticks))
	w.model = "falloff" if d.has("damage_near") else "flat"
	w.damage_body = int(d.get("damage_body", w.damage_body))
	w.damage_head = int(d.get("damage_head", w.damage_head))
	w.damage_legs = int(d.get("damage_legs", w.damage_legs))
	w.legs_below_height = float(d.get("legs_below_height", w.legs_below_height))
	w.scope_in_ticks = int(d.get("scope_in_ticks", w.scope_in_ticks))
	w.hip_spread_deg = float(d.get("hip_spread_deg", w.hip_spread_deg))
	w.ads_spread_deg = float(d.get("ads_spread_deg", w.ads_spread_deg))
	w.recoil_kick_deg = float(d.get("recoil_kick_deg", w.recoil_kick_deg))
	w.damage_near = int(d.get("damage_near", w.damage_near))
	w.damage_far = int(d.get("damage_far", w.damage_far))
	w.headshot_multiplier = float(d.get("headshot_multiplier", w.headshot_multiplier))
	w.falloff_start_m = float(d.get("falloff_start_m", w.falloff_start_m))
	w.falloff_end_m = float(d.get("falloff_end_m", w.falloff_end_m))
	w.ads_in_ticks = int(d.get("ads_in_ticks", w.ads_in_ticks))
	w.spread_deg = float(d.get("spread_deg", w.spread_deg))
	w.ads_recoil_multiplier = float(d.get("ads_recoil_multiplier", w.ads_recoil_multiplier))
	w.recoil_reset_ticks = int(d.get("recoil_reset_ticks", w.recoil_reset_ticks))
	for p in d.get("recoil_pattern_deg", []):
		w.recoil_pattern_deg.append(Vector2(float(p[0]), float(p[1])))
	return w


## Load every weapon in the loadout order from a weapons table.
static func load_all(table: Dictionary) -> Array[WeaponDef]:
	var out: Array[WeaponDef] = []
	for id in table.get("loadout", []):
		var sid := str(id)
		if table.has(sid):
			out.append(from_dict(sid, table[sid]))
	return out


## Load a specific list of weapon ids (a minigame's manifest loadout).
static func load_ids(table: Dictionary, ids: Array) -> Array[WeaponDef]:
	var out: Array[WeaponDef] = []
	for id in ids:
		var sid := str(id)
		if table.has(sid):
			out.append(from_dict(sid, table[sid]))
	return out


func is_sniper() -> bool:
	return model == "flat"


## Damage for a hit. hit_kind: HitscanResolver.HEAD / BODY. hit_height is metres above the
## victim's feet (for the sniper's leg rule). distance in metres.
func damage_for(hit_kind: int, distance: float, hit_height: float) -> int:
	if model == "flat":
		if hit_kind == 2:
			return damage_head
		if hit_height < legs_below_height:
			return damage_legs
		return damage_body
	var span := maxf(0.001, falloff_end_m - falloff_start_m)
	var f := clampf((distance - falloff_start_m) / span, 0.0, 1.0)
	var base := lerpf(float(damage_near), float(damage_far), f)
	if hit_kind == 2:
		base *= headshot_multiplier
	return int(round(base))
