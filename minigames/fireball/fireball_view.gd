class_name FireballView
extends Node3D
## The fireball's look (Sean, 2026-09-25: "a circular orb with an aura around it that's a similar
## color... an electrifying orb, keep it the same color"; the flame tongues of the day before are
## gone): a light-blue orb inside two translucent aura shells of the same blue, arcs of the pale
## core colour crawling over the aura and flickering, a trail of sparks behind its flight, a light
## on it, and the hum. Shown from a dead-reckoned position (the last state plus its velocity),
## eased toward every fresh state, so a client's ball moves as smoothly as the host's. Meshes and
## materials are built once and shared; the arcs are a pool of thin boxes re-laid every few
## frames, nothing is made while it flies.

const SPARKS := 14
const BOLTS := 10
const BOLT_SEGMENTS := 4
const CORE_R := 0.31        # the orb, metres
const AURA_R := 0.56        # the inner aura shell
const AURA_OUTER_R := 0.78  # the outer, fainter one

static var _sphere_mesh: SphereMesh
static var _box_mesh: BoxMesh
static var _mats: Dictionary = {}
static var _hum_stream: AudioStreamWAV

var _core: MeshInstance3D
var _aura: MeshInstance3D
var _aura_outer: MeshInstance3D
var _bolts: Array = []               # BOLTS lists of BOLT_SEGMENTS MeshInstance3D
var _bolt_life: Array[float] = []
var _light: OmniLight3D
var _sparks: Array[MeshInstance3D] = []
var _spark_age: Array[float] = []
var _spark_next: int = 0
var _spark_timer: float = 0.0
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
		_sphere_mesh.radial_segments = 24
		_sphere_mesh.rings = 12
	return _sphere_mesh


static func _box() -> BoxMesh:
	if _box_mesh == null:
		_box_mesh = BoxMesh.new()
		_box_mesh.size = Vector3.ONE
	return _box_mesh


## Flat, unshaded light (not a lit surface), one material per tone and alpha, kept for the run.
## A translucent shell gets a render priority so the two auras draw inner first, outer last.
static func material(key: String, map_id: String, alpha: float = 1.0, priority: int = 0) -> StandardMaterial3D:
	var k := "%s|%s|%.2f|%d" % [map_id, key, alpha, priority]
	if not _mats.has(k):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		var c := Palette.map_colour(map_id, key)
		m.albedo_color = Color(c.r, c.g, c.b, alpha)
		if alpha < 1.0:
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.render_priority = priority
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
	# The orb, then the aura: an inner shell of the same blue at a third, an outer one fainter.
	_core = _node(_mesh(), material("fire_core", map_id), CORE_R * 2.0)
	_core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_aura = _node(_mesh(), material("fire", map_id, 0.5, 1), AURA_R * 2.0)
	_aura_outer = _node(_mesh(), material("fire", map_id, 0.22, 2), AURA_OUTER_R * 2.0)   # the same bright blue: a darker one at low alpha went grey over the cream sky
	# The arcs: a pool of jagged lines in the core's pale blue, laid over the aura and re-laid as
	# they flicker (electrifying, Sean's word).
	var bolt_mat := material("fire_core", map_id)
	for i in BOLTS:
		var segs: Array = []
		for k in BOLT_SEGMENTS:
			var seg := MeshInstance3D.new()
			seg.mesh = _box()
			seg.material_override = bolt_mat
			seg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			seg.visible = false
			add_child(seg)
			segs.append(seg)
		_bolts.append(segs)
		_bolt_life.append(0.0)
	_light = OmniLight3D.new()
	_light.light_color = Palette.map_colour(map_id, "glow")
	_light.light_energy = 2.2
	_light.omni_range = 9.0
	_light.shadow_enabled = false
	add_child(_light)
	# The trail: sparks the orb leaves behind, tiny and fading.
	for i in SPARKS:
		var p := MeshInstance3D.new()
		p.mesh = _mesh()
		p.material_override = material("fire_core" if i % 2 == 0 else "fire", map_id, 0.8, 3)
		p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		p.top_level = true
		p.visible = false
		add_child(p)
		_sparks.append(p)
		_spark_age.append(99.0)
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


## The hit: the ball bursts and is gone; its sparks stay and fade.
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


## One arc re-laid: a jagged line between two random points on the aura, jittered off it.
func _lay_bolt(i: int) -> void:
	var a := Vector3(_rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 1.0)).normalized()
	var axis := a.cross(Vector3(_rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 1.0))).normalized()
	if axis.length_squared() < 0.5:
		axis = a.cross(Vector3.UP).normalized()
	var arc := _rng.randf_range(0.5, 1.3)   # radians of aura the arc spans
	var r := lerpf(AURA_R, AURA_OUTER_R, 0.4)
	var points: Array[Vector3] = []
	for k in BOLT_SEGMENTS + 1:
		var t := float(k) / float(BOLT_SEGMENTS)
		var p := a.rotated(axis, arc * t) * r
		if k > 0 and k < BOLT_SEGMENTS:
			p += Vector3(_rng.randf_range(-0.09, 0.09), _rng.randf_range(-0.09, 0.09), _rng.randf_range(-0.09, 0.09))
		points.append(p)
	var segs: Array = _bolts[i]
	for k in BOLT_SEGMENTS:
		var seg: MeshInstance3D = segs[k]
		var from := points[k]
		var to := points[k + 1]
		var d := to - from
		seg.position = (from + to) * 0.5
		if d.length() > 1e-4:
			seg.look_at(global_position + seg.position + d, Vector3.UP if absf(d.normalized().dot(Vector3.UP)) < 0.98 else Vector3.RIGHT)
		seg.scale = Vector3(0.055, 0.055, maxf(d.length(), 0.01))   # thick enough for the pale fill to show inside the ink outline
		seg.visible = true
	_bolt_life[i] = _rng.randf_range(0.05, 0.12)


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
	# The orb breathes a little, the aura swells with the speed level and pulses; the light flickers.
	var t := now * 7.0
	var grow := 1.0 + 0.05 * float(_level)
	_core.scale = Vector3.ONE * (CORE_R * 2.0) * (1.0 + 0.03 * sin(t * 1.7))
	_aura.scale = Vector3.ONE * (AURA_R * 2.0) * grow * (1.0 + 0.06 * sin(t))
	_aura_outer.scale = Vector3.ONE * (AURA_OUTER_R * 2.0) * grow * (1.0 + 0.05 * sin(t * 1.3 + 1.0))
	if _light != null:
		_light.light_energy = 2.2 + 0.5 * sin(now * 23.0) * sin(now * 31.0)
	# The arcs flicker: each lives a few frames, then is gone until it is re-laid somewhere else.
	for i in BOLTS:
		_bolt_life[i] -= delta
		if _bolt_life[i] <= 0.0:
			var segs: Array = _bolts[i]
			if segs[0].visible:
				for seg in segs:
					seg.visible = false
			if _rng.randf() < delta * 14.0:
				_lay_bolt(i)
	if _hum != null:
		_hum.pitch_scale = clampf(0.9 + 0.045 * float(_level), 0.8, 1.9)
	# The trail: a spark every few centimetres of flight, fading and shrinking.
	if _flying:
		_spark_timer += delta
		if _spark_timer >= 0.03:
			_spark_timer = 0.0
			var p := _sparks[_spark_next]
			_spark_age[_spark_next] = 0.0
			_spark_next = (_spark_next + 1) % SPARKS
			p.visible = true
			p.global_position = global_position - _net_vel.normalized() * 0.35 + Vector3(_rng.randf_range(-0.3, 0.3), _rng.randf_range(-0.3, 0.3), _rng.randf_range(-0.3, 0.3))
	for i in SPARKS:
		if not _sparks[i].visible:
			continue
		_spark_age[i] += delta
		var k := _spark_age[i] / 0.32
		if k >= 1.0:
			_sparks[i].visible = false
			continue
		_sparks[i].scale = Vector3.ONE * lerpf(0.16, 0.03, k)
		_sparks[i].transparency = k
