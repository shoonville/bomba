class_name FireballView
extends Node3D
## The fireball's look (Sean: "the fireball is lightblue fire"): a white-hot core in a shell of
## flame tongues that stream behind its flight and lick upward when it hovers, a light on it,
## and a trail of puffs it leaves and that fade behind it. Shown from a dead-reckoned position
## (the last state plus its velocity), eased toward every fresh state, so a client's ball moves
## as smoothly as the host's. The hum is a looping synth on a 3D player, its pitch up with the
## speed. Meshes and materials are built once and shared (a burst per reflect is the Burst's
## own shared star); nothing is made per hit.

const PUFFS := 14
const TONGUES := 9

static var _sphere_mesh: SphereMesh
static var _mats: Dictionary = {}
static var _hum_stream: AudioStreamWAV

var _core: MeshInstance3D
var _shell: MeshInstance3D
var _tongues: Array[MeshInstance3D] = []
var _light: OmniLight3D
var _puffs: Array[MeshInstance3D] = []
var _puff_age: Array[float] = []
var _puff_next: int = 0
var _puff_timer: float = 0.0
var _hum: AudioStreamPlayer3D
var _rng := RandomNumberGenerator.new()

var _net_pos: Vector3 = Vector3.ZERO
var _net_vel: Vector3 = Vector3.ZERO
var _net_time: float = 0.0
var _shown: bool = false
var _pop: float = 0.0      # a scale pop on a reflect
var _appear: float = 0.0   # scaling in from the spawn
var _flying: bool = false
var _level: int = 0
var _map: String = "fireball"


static func _mesh() -> SphereMesh:
	if _sphere_mesh == null:
		_sphere_mesh = SphereMesh.new()
		_sphere_mesh.radius = 0.5
		_sphere_mesh.height = 1.0
		_sphere_mesh.radial_segments = 16
		_sphere_mesh.rings = 8
	return _sphere_mesh


## Flat, unshaded fire (a light, not a lit surface), one material per tone, kept for the run.
static func material(key: String, map_id: String, alpha: float = 1.0) -> StandardMaterial3D:
	var k := "%s|%s|%.2f" % [map_id, key, alpha]
	if not _mats.has(k):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		var c := Palette.map_colour(map_id, key)
		m.albedo_color = Color(c.r, c.g, c.b, alpha)
		if alpha < 1.0:
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_mats[k] = m
	return _mats[k]


## The hum loop, synthesised once.
static func hum_stream() -> AudioStreamWAV:
	if _hum_stream == null:
		_hum_stream = SoundSynth.to_wav(SoundSynth.build("fireball_hum"), true, 0.7)
	return _hum_stream


func build(map_id: String) -> void:
	_map = map_id
	_rng.seed = 4711
	_core = _node(_mesh(), material("fire_core", map_id), 0.62)
	_core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_shell = _node(_mesh(), material("fire", map_id, 0.55), 0.95)
	for i in TONGUES:
		var t := _node(_mesh(), material("fire" if i % 2 == 0 else "fire_dark", map_id), 1.0)
		_tongues.append(t)
	_light = OmniLight3D.new()
	_light.light_color = Palette.map_colour(map_id, "glow")
	_light.light_energy = 2.2
	_light.omni_range = 9.0
	_light.shadow_enabled = false
	add_child(_light)
	for i in PUFFS:
		var p := MeshInstance3D.new()
		p.mesh = _mesh()
		p.material_override = material("fire_dark" if i % 3 == 0 else "fire", map_id, 0.7)
		p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		p.top_level = true
		p.visible = false
		add_child(p)
		_puffs.append(p)
		_puff_age.append(99.0)
	_hum = AudioStreamPlayer3D.new()
	_hum.stream = hum_stream()
	_hum.bus = "SFX"
	_hum.max_distance = 60.0
	_hum.unit_size = 5.0
	_hum.volume_db = -8.0
	_hum.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	add_child(_hum)
	visible = false


func _node(mesh: Mesh, mat: Material, size: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.scale = Vector3.ONE * size
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


## A fresh state from the simulation (the host's own, or the one it sent): where the ball is
## and where it is going; `flying` false while it hovers over its spawn.
func set_state(pos: Vector3, vel: Vector3, flying: bool, level: int) -> void:
	var was_shown := _shown
	if was_shown and pos == _net_pos:
		vel = Vector3.ZERO   # a ball that did not move (the round over's freeze): no reckoning ahead of it
	_net_pos = pos
	_net_vel = vel
	_net_time = Time.get_ticks_msec() / 1000.0
	_flying = flying
	_level = level
	if not was_shown:
		show_ball(pos)


func show_ball(at: Vector3) -> void:
	_shown = true
	visible = true
	global_position = at
	_net_pos = at
	_appear = 1.0
	if Audio.enabled and _hum != null and not _hum.playing:
		_hum.play()


func hide_ball() -> void:
	_shown = false
	visible = false
	if _hum != null and _hum.playing:
		_hum.stop()


func is_shown() -> bool:
	return _shown


## The reflect: a pop and a burst in the ball's blue at the ball.
func reflected(at: Vector3, effects: Node) -> void:
	_pop = 1.0
	global_position = at
	_net_pos = at
	Burst.spawn(effects, at, Palette.map_colour(_map, "fire"), 0.5, 0.22, 9)   # a metre from the reflector's eye: small, or it fills the view
	Burst.spawn(effects, at, Palette.map_colour(_map, "fire_core"), 0.3, 0.16, 7)


## The hit: the ball bursts and is gone; its puffs stay and fade.
func burst(at: Vector3, effects: Node) -> void:
	Burst.spawn(effects, at, Palette.map_colour(_map, "fire"), 1.6, 0.34, 9)
	Burst.spawn(effects, at, Palette.map_colour(_map, "fire_core"), 0.9, 0.26, 8)
	Burst.spawn(effects, at, Palette.hud_colour("ink"), 2.0, 0.2, 7)
	hide_ball()


## The kill cam: the ball where it was at a replayed tick, or hidden (the hum stays off).
func replay_at(pos: Vector3, shown: bool) -> void:
	visible = shown
	if shown:
		global_position = pos
		_net_pos = pos
		_net_vel = Vector3.ZERO


func _process(delta: float) -> void:
	if not visible:
		return
	# Dead reckoning eased toward the latest state; a snap when far from it (a respawn).
	var now := Time.get_ticks_msec() / 1000.0
	var target := _net_pos + _net_vel * (now - _net_time)
	var next := global_position + _net_vel * delta
	if (next - target).length() > 3.0:
		next = target
	else:
		next = next.lerp(target, 1.0 - exp(-delta * 14.0))
	global_position = next
	_appear = maxf(0.0, _appear - delta * 4.0)
	_pop = maxf(0.0, _pop - delta * 5.0)
	var s := (1.0 - pow(_appear, 2.0)) * (1.0 + 0.35 * sin(_pop * PI))
	scale = Vector3.ONE * maxf(s, 0.01)
	# The flames stream behind the flight, or up when hovering: each tongue an elongated sphere
	# jittering in length and lean.
	var back := -_net_vel.normalized() if (_flying and _net_vel.length() > 0.5) else Vector3.UP
	var t := now * 9.0
	for i in TONGUES:
		var tongue := _tongues[i]
		var a := TAU * float(i) / float(TONGUES) + sin(t * 0.7 + i) * 0.3
		var side := back.cross(Vector3.UP if absf(back.y) < 0.9 else Vector3.RIGHT).normalized()
		var side2 := back.cross(side).normalized()
		var lean := (side * cos(a) + side2 * sin(a)) * 0.28
		var length := 0.45 + 0.22 * float(i % 3) + 0.25 * sin(t + i * 1.7) + 0.08 * float(_level)
		var dir := (back + lean).normalized()
		tongue.position = dir * (0.25 + length * 0.45)
		if absf(dir.dot(Vector3.UP)) < 0.999:
			tongue.look_at(global_position + dir, Vector3.UP)
		else:
			tongue.look_at(global_position + dir, Vector3.RIGHT)
		tongue.scale = Vector3(0.30 + 0.05 * sin(t * 1.3 + i), 0.30 + 0.05 * cos(t + i), length)
	_shell.scale = Vector3.ONE * (0.95 + 0.06 * sin(t * 1.9))
	_core.scale = Vector3.ONE * (0.62 + 0.04 * sin(t * 2.3))
	if _hum != null:
		_hum.pitch_scale = clampf(0.9 + 0.045 * float(_level), 0.8, 1.9)
	# The trail: a puff left every few centimetres of flight, fading and shrinking.
	if _flying:
		_puff_timer += delta
		if _puff_timer >= 0.028:
			_puff_timer = 0.0
			var p := _puffs[_puff_next]
			_puff_age[_puff_next] = 0.0
			_puff_next = (_puff_next + 1) % PUFFS
			p.visible = true
			p.global_position = global_position - _net_vel.normalized() * 0.3 + Vector3(_rng.randf_range(-0.15, 0.15), _rng.randf_range(-0.15, 0.15), _rng.randf_range(-0.15, 0.15))
	for i in PUFFS:
		if not _puffs[i].visible:
			continue
		_puff_age[i] += delta
		var k := _puff_age[i] / 0.4
		if k >= 1.0:
			_puffs[i].visible = false
			continue
		_puffs[i].scale = Vector3.ONE * lerpf(0.6, 0.12, k)
		_puffs[i].transparency = k
