class_name Wipe
extends Control
## Screen transition (STYLE.md §7: wipes and slams, not fades). A diagonal band in the accent
## colour with an ink edge sweeps across. cover() → callback → reveal(); slam() reveals from a
## full cover for switches that must happen synchronously (RPC-driven scene changes).

var progress: float = 0.0
var phase: String = "idle"   # idle, cover, hold (a full cover held while a scene builds), reveal
var _accent: Color
var _ink: Color
var _paper: Color
var _tw: Tween


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_accent = Palette.map_colour("menu", "accent")
	_ink = Palette.map_colour("menu", "line")
	_paper = Palette.hud_colour("paper")


func is_busy() -> bool:
	return phase != "idle"


## Full transition: cover the screen, run the callback while covered, reveal.
func run(on_covered: Callable, duration: float = 0.24) -> void:
	if is_busy():
		on_covered.call()
		return
	mouse_filter = Control.MOUSE_FILTER_STOP
	phase = "cover"
	progress = 0.0
	_tw = create_tween()
	_tw.tween_method(_set_progress, 0.0, 1.0, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_tw.tween_callback(func():
		on_covered.call()
		phase = "reveal"
		progress = 0.0
	)
	_tw.tween_method(_set_progress, 0.0, 1.0, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_tw.tween_callback(_finish)


## Cover the screen at once and hold it, for a switch that builds over several frames under it;
## slam() reveals when it is done. A reveal in flight (the board's own) is cut, or it would open
## the cover over the half-built scene.
func hold() -> void:
	if _tw != null and _tw.is_valid():
		_tw.kill()
	mouse_filter = Control.MOUSE_FILTER_STOP
	phase = "hold"
	progress = 0.0
	queue_redraw()


## Reveal from a full cover (the switch already happened, or was built under hold()).
func slam(duration: float = 0.3) -> void:
	if is_busy() and phase != "hold":
		return
	mouse_filter = Control.MOUSE_FILTER_STOP
	phase = "reveal"
	progress = 0.0
	queue_redraw()
	_tw = create_tween()
	_tw.tween_method(_set_progress, 0.0, 1.0, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_tw.tween_callback(_finish)


func _finish() -> void:
	phase = "idle"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()


func _set_progress(v: float) -> void:
	progress = v
	queue_redraw()


func _draw() -> void:
	if phase == "idle":
		return
	var w := size.x
	var h := size.y
	var skew := h * 0.22
	var edge_w := 26.0
	var poly := PackedVector2Array()
	var stripe := PackedVector2Array()
	if phase == "cover":
		var x := lerpf(-skew * 2.0, w + skew * 2.0, progress)
		poly = PackedVector2Array([Vector2(-skew * 3.0, 0), Vector2(x + skew, 0), Vector2(x - skew, h), Vector2(-skew * 3.0, h)])
		stripe = PackedVector2Array([Vector2(x + skew - edge_w, 0), Vector2(x + skew, 0), Vector2(x - skew, h), Vector2(x - skew - edge_w, h)])
	else:
		# reveal, and hold (progress 0: the band covers everything)
		var x := lerpf(-skew * 2.0, w + skew * 2.0, progress)
		poly = PackedVector2Array([Vector2(x + skew, 0), Vector2(w + skew * 3.0, 0), Vector2(w + skew * 3.0, h), Vector2(x - skew, h)])
		stripe = PackedVector2Array([Vector2(x + skew, 0), Vector2(x + skew + edge_w, 0), Vector2(x - skew + edge_w, h), Vector2(x - skew, h)])
	draw_colored_polygon(poly, _accent)
	draw_colored_polygon(stripe, _ink)
