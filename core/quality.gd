class_name AutoQuality
extends Node
## Keeps the GPU under budget on any machine without a settings visit: steps the 3D render
## scale down from the player's RENDER SCALE cap when the renderer's own GPU time (the frame's
## measured timestamps) runs over budget, and back up when there is room. The budget is a 60 Hz
## frame's worth: the GPU may take 70 % of 16.7 ms, whatever the monitor's refresh rate, so a
## fast monitor never trades sharpness for frames above 60. Steps are 0.25 between 0.75 and the
## cap, at most one every 3 s, and a step up needs 5 calm seconds with room for the 1.4–1.6×
## more pixels it brings. Samples over 100 ms (hitches) and the first 2 s after a scene switch
## (its build frames) are ignored. --render_scale=N pins the scale and turns this off.

const STEP := 0.25
const FLOOR := 0.75
const HOLD_SECONDS := 3.0                 # between changes
const CALM_SECONDS := 5.0                 # under the step-up line before stepping up
const SETTLE_SECONDS := 2.0               # after a scene switch

var budget_ms: float = 0.7 * 1000.0 / 60.0   # 11.7 ms of GPU per frame; --gpu_budget_ms=N to test
var cap: float = 1.5
var current: float = 1.5
var enabled: bool = true

var _samples: PackedFloat32Array = []
var _second: float = 0.0
var _since_change: float = HOLD_SECONDS
var _calm: float = 0.0
var _settle: float = SETTLE_SECONDS
var _last_scene: int = 0


func set_cap(p_cap: float) -> void:
	cap = clampf(p_cap, FLOOR, 2.0)
	if current > cap or not enabled:
		_apply(cap)


func notify_scene_change() -> void:
	_settle = SETTLE_SECONDS
	_samples.clear()


func _process(delta: float) -> void:
	if not enabled or Game.headless:
		return
	var scene := 0
	if Game.active_minigame != null:
		scene = Game.active_minigame.get_instance_id()
	elif Game.board != null:
		scene = Game.board.get_instance_id()
	if scene != _last_scene:
		_last_scene = scene
		notify_scene_change()
	if scene == 0:
		return
	_since_change += delta
	if _settle > 0.0:
		_settle -= delta
		return
	var gpu := RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid())
	if gpu > 0.0 and gpu < 100.0:
		_samples.append(gpu)
	_second += delta
	if _second < 1.0:
		return
	_second = 0.0
	if _samples.size() < 10:
		return
	var s := _samples.duplicate()
	s.sort()
	var p90 := s[int(0.9 * (s.size() - 1))]
	_samples.clear()
	if p90 > budget_ms:
		_calm = 0.0
		if current > FLOOR and _since_change >= HOLD_SECONDS:
			_apply(current - STEP)
			Log.info("perf", "Auto quality: render scale %.2f (GPU %.1f ms p90 over the %.1f ms budget)" % [current, p90, budget_ms])
	elif p90 < budget_ms * 0.55:
		_calm += 1.0
		if current < cap and _calm >= CALM_SECONDS and _since_change >= HOLD_SECONDS:
			_apply(minf(current + STEP, cap))
			_calm = 0.0
			Log.info("perf", "Auto quality: render scale %.2f (GPU %.1f ms p90, room to spare)" % [current, p90])
	else:
		_calm = 0.0


func _apply(scale: float) -> void:
	current = clampf(scale, FLOOR, cap)
	_since_change = 0.0
	var vp := get_viewport()
	if vp != null:
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
		vp.scaling_3d_scale = current
