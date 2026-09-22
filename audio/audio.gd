extends Node
## Audio module (DESIGN.md §4): buses, procedural sound cache, one-shot players, 3D players,
## music with fades. Autoload `Audio`. Everything it plays is synthesised by SoundSynth; nothing
## is loaded from disk. Gameplay talks to it through Events; UI calls it directly.

const POOL_2D := 12
const POOL_3D := 16

var _streams: Dictionary = {}
var _players_2d: Array[AudioStreamPlayer] = []
var _players_3d: Array[AudioStreamPlayer3D] = []
var _music_player: AudioStreamPlayer
var _music_name: String = ""
var _music_thread: Thread
var _music_pending: String = ""
var _bolt_timer: SceneTreeTimer
var enabled: bool = true


func _ready() -> void:
	enabled = not Game.headless if Game != null else true
	_setup_buses()
	for i in POOL_2D:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_players_2d.append(p)
	for i in POOL_3D:
		var p := AudioStreamPlayer3D.new()
		p.bus = "SFX"
		p.max_distance = 80.0
		p.unit_size = 6.0
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		add_child(p)
		_players_3d.append(p)
	_music_player = AudioStreamPlayer.new()
	_music_player.bus = "Music"
	add_child(_music_player)
	if enabled:
		var t0 := Time.get_ticks_msec()
		for n in SoundSynth.names():
			_streams[n] = SoundSynth.to_wav(SoundSynth.build(n))
		Log.info("audio", "Synthesised %d sounds in %d ms" % [_streams.size(), Time.get_ticks_msec() - t0])
	Settings.changed.connect(_apply_volumes)
	_apply_volumes()
	_connect_events()


func _setup_buses() -> void:
	for name in ["Music", "SFX", "UI"]:
		if AudioServer.get_bus_index(name) < 0:
			AudioServer.add_bus()
			var idx := AudioServer.get_bus_count() - 1
			AudioServer.set_bus_name(idx, name)
			AudioServer.set_bus_send(idx, "Master")


func _apply_volumes() -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(clampf(Settings.volume_master, 0.0001, 1.0)))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Music"), linear_to_db(clampf(Settings.volume_music, 0.0001, 1.0)) - 10.0)
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("SFX"), linear_to_db(clampf(Settings.volume_sfx, 0.0001, 1.0)))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("UI"), linear_to_db(clampf(Settings.volume_ui, 0.0001, 1.0)) - 4.0)


func _connect_events() -> void:
	Events.local_fired.connect(func(weapon: String):
		play("sniper_fire" if weapon == "sniper" else "ar_fire", 0.0, _jitter(0.04))
		if weapon == "sniper":
			get_tree().create_timer(0.32).timeout.connect(func(): play("bolt", -4.0))
	)
	Events.local_hit_predicted.connect(func(kind: int, _victim: int):
		play("headshot" if kind == HitscanResolver.HEAD else "hitmarker", -2.0)
	)
	Events.kill.connect(func(killer: int, victim: int, _w: String, _hs: bool, _t: int):
		var me := multiplayer.get_unique_id()
		if killer == me and victim != me:
			play("kill", -3.0)
		elif victim == me:
			play("death", -2.0)
	)
	Events.local_damaged.connect(func(_amount: int, _from: int): play("hurt", -5.0, _jitter(0.08)))
	Events.local_respawned.connect(func(): play("respawn", -6.0))
	Events.local_weapon_event.connect(func(name: String):
		match name:
			"reload_started": play("reload_start", -6.0)
			"reload_finished": play("reload_end", -6.0)
			"reload_round": play("shell_in", -4.0, _jitter(0.06))
			"dry_fire": play("dry", -8.0)
			"swapped": play("swap", -8.0)
	)
	Events.local_footstep.connect(func(): play("footstep", -14.0, _jitter(0.12)))
	Events.local_jump.connect(func(): play("jump", -14.0))
	Events.local_land.connect(func(): play("land", -10.0))
	Events.round_started.connect(func(_end_tick: int): play("round_start", -6.0))
	Events.round_ended.connect(func(): play("round_end", -4.0))
	Events.hill_moved.connect(func(_index: int): play("hill_move", -6.0))
	Events.hill_tick.connect(func(): play("hill_tick", -14.0))
	Events.remote_shot.connect(func(weapon: String, origin: Vector3):
		play_at("sniper_fire" if weapon == "sniper" else "ar_fire", origin, -4.0, _jitter(0.05))
	)
	Events.ui_sound.connect(func(name: String): play(name, 0.0, 1.0, "UI"))


func _jitter(amount: float) -> float:
	return 1.0 + Rng.stream("audio").randf_range(-amount, amount)


func stream(name: String) -> AudioStreamWAV:
	if not _streams.has(name):
		_streams[name] = SoundSynth.to_wav(SoundSynth.build(name))
	return _streams[name]


func play(name: String, volume_db: float = 0.0, pitch: float = 1.0, bus: String = "SFX") -> void:
	if not enabled:
		return
	for p in _players_2d:
		if not p.playing:
			p.stream = stream(name)
			p.volume_db = volume_db
			p.pitch_scale = pitch
			p.bus = bus
			p.play()
			return


func play_at(name: String, position: Vector3, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	if not enabled:
		return
	for p in _players_3d:
		if not p.playing:
			p.stream = stream(name)
			p.volume_db = volume_db
			p.pitch_scale = pitch
			p.global_position = position
			p.play()
			return


## Start a music loop by name (synthesised on a thread the first time), with a short fade.
## Music is off for now (Sean, 2026-09-18). The loops still build and test; flip this to hear them.
const MUSIC_ENABLED := false


func music(name: String) -> void:
	if not MUSIC_ENABLED:
		if _music_player != null and _music_player.playing:
			_music_player.stop()
		return
	if not enabled or name == _music_name:
		return
	_music_name = name
	if name == "":
		_fade_out()
		return
	if _streams.has(name):
		_start_music(_streams[name])
		return
	if _music_thread != null and _music_thread.is_started():
		_music_pending = name
		return
	_music_thread = Thread.new()
	_music_thread.start(_synth_music.bind(name))


func _synth_music(name: String) -> void:
	var buf: PackedFloat32Array
	match name:
		"music_menu":
			buf = SoundSynth.build_music_menu()
		"music_match":
			buf = SoundSynth.build_music_match()
		_:
			buf = SoundSynth.build_music_menu()
	var wav := SoundSynth.to_wav(buf, true, 0.8)
	_on_music_ready.call_deferred(name, wav)


func _on_music_ready(name: String, wav: AudioStreamWAV) -> void:
	if _music_thread != null:
		_music_thread.wait_to_finish()
		_music_thread = null
	_streams[name] = wav
	if _music_name == name:
		_start_music(wav)
	if _music_pending != "":
		var pending := _music_pending
		_music_pending = ""
		music(pending)


func _start_music(wav: AudioStreamWAV) -> void:
	_music_player.stream = wav
	_music_player.volume_db = -18.0
	_music_player.play()
	var tw := create_tween()
	tw.tween_property(_music_player, "volume_db", 0.0, 0.8)


func _fade_out() -> void:
	if not _music_player.playing:
		return
	var tw := create_tween()
	tw.tween_property(_music_player, "volume_db", -30.0, 0.5)
	tw.tween_callback(_music_player.stop)


func _exit_tree() -> void:
	if _music_thread != null and _music_thread.is_started():
		_music_thread.wait_to_finish()
