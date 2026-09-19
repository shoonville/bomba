class_name LogoMark
extends Control
## The BOMBA wordmark, drawn rather than typeset: chunky round-stroke letters that overlap like
## a throw-up, a heavy ink outline, a hard colour drop layer behind them and one spark. No font,
## no asset (DESIGN.md asset policy). Colours: palette.json menu.logo_fill / logo_ink /
## logo_drop / logo_spark. Letters stay upright; the bounce is a few pixels of baseline.

var text: String = "BOMBA"
var cap: float = 150.0
var fill: Color = Color.WHITE
var ink: Color = Color.BLACK
var drop: Color = Color.CYAN
var spark: Color = Color.YELLOW

const STROKE := 27.0      # in letter units (cap height = 100)
const OUTLINE := 9.0
const DROP := Vector2(10.0, 12.0)
const OVERLAP := 8.0      # letter units the next letter's ink bites into the previous one
const MARGIN := 26.0
const BOUNCE := [0.0, 5.0, -4.0, 4.0, -3.0]
const WOBBLE := [1.0, 0.97, 1.03, 0.98, 1.02]


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	fill = Palette.map_colour("menu", "logo_fill")
	ink = Palette.map_colour("menu", "logo_ink")
	drop = Palette.map_colour("menu", "logo_drop")
	spark = Palette.map_colour("menu", "logo_spark")
	custom_minimum_size = measure()
	size = custom_minimum_size


static func letter(ch: String) -> Dictionary:
	match ch:
		"B":
			return {"w": 54.0,
				"strokes": [[Vector2(0, 0), Vector2(0, 100)], [Vector2(0, 100), Vector2(24, 100)],
					[Vector2(0, 52), Vector2(26, 52)], [Vector2(0, 0), Vector2(28, 0)]],
				"arcs": [[24.0, 76.0, 24.0, -90.0, 90.0], [28.0, 26.0, 26.0, -90.0, 90.0]], "ellipse": []}
		"O":
			return {"w": 74.0, "strokes": [], "arcs": [], "ellipse": [37.0, 50.0, 37.0, 50.0]}
		"M":
			return {"w": 88.0, "strokes": [[Vector2(0, 0), Vector2(0, 100), Vector2(44, 42), Vector2(88, 100), Vector2(88, 0)]],
				"arcs": [], "ellipse": []}
		"A":
			return {"w": 80.0, "strokes": [[Vector2(0, 0), Vector2(40, 100), Vector2(80, 0)], [Vector2(17, 34), Vector2(63, 34)]],
				"arcs": [], "ellipse": []}
	return {"w": 60.0, "strokes": [[Vector2(0, 0), Vector2(0, 100)]], "arcs": [], "ellipse": []}


## Advance of a letter: its ink extent (width + stroke) minus the overlap into the next one.
static func advance(ch: String) -> float:
	return float(letter(ch)["w"]) + STROKE - OVERLAP


func measure() -> Vector2:
	var s := cap / 100.0
	var w := 0.0
	for i in text.length():
		w += advance(text[i]) * s
	w += (OVERLAP + OUTLINE * 2.0) * s
	return Vector2(w + (MARGIN * 2.0 + DROP.x) * s, cap + (MARGIN * 2.0 + DROP.y + STROKE + OUTLINE * 2.0) * s)


func _draw() -> void:
	var s := cap / 100.0
	var origin := Vector2((MARGIN + STROKE * 0.5 + OUTLINE) * s, (MARGIN + STROKE * 0.5 + OUTLINE) * s + cap)
	var xs: Array = []
	var x := origin.x
	for i in text.length():
		xs.append(x)
		x += advance(text[i]) * s
	# 1. the drop layer for every letter (ink rim, then colour), 2. the letters in order
	for i in text.length():
		var o := origin + Vector2(xs[i] - origin.x, BOUNCE[i % BOUNCE.size()] * s) + DROP * s
		_draw_letter(text[i], o, s * WOBBLE[i % WOBBLE.size()], ink, (STROKE + OUTLINE * 2.0))
		_draw_letter(text[i], o, s * WOBBLE[i % WOBBLE.size()], drop, STROKE)
	for i in text.length():
		var o := origin + Vector2(xs[i] - origin.x, BOUNCE[i % BOUNCE.size()] * s)
		_draw_letter(text[i], o, s * WOBBLE[i % WOBBLE.size()], ink, (STROKE + OUTLINE * 2.0))
		_draw_letter(text[i], o, s * WOBBLE[i % WOBBLE.size()], fill, STROKE)
	# the spark: a four-point star off the last letter's shoulder
	var last := letter(text[text.length() - 1])
	var sp := Vector2(xs[text.length() - 1] + (float(last["w"]) + STROKE * 0.5 + 2.0) * s, origin.y - cap - 4.0 * s)
	var star := PackedVector2Array()
	for k in 8:
		var r := (22.0 if k % 2 == 0 else 7.0) * s
		var a := k * PI / 4.0
		star.append(sp + Vector2(cos(a), sin(a)) * r)
	var star_outline := star.duplicate()
	star_outline.append(star[0])
	draw_polyline(star_outline, ink, 6.0 * s, true)
	draw_colored_polygon(star, spark)


## One letter: strokes and arcs in letter units (y up), drawn with round joins and caps.
func _draw_letter(ch: String, o: Vector2, s: float, col: Color, width_units: float) -> void:
	var l := letter(ch)
	var w := width_units * s
	for stroke in l["strokes"]:
		var pts := PackedVector2Array()
		for p in stroke:
			pts.append(o + Vector2(p.x * s, -p.y * s))
		# Segments one at a time with round joins: a wide polyline would miter the M's and A's
		# corners into spikes.
		for k in pts.size() - 1:
			draw_line(pts[k], pts[k + 1], col, w, true)
		for p in pts:
			draw_circle(p, w * 0.5, col)
	for a in l["arcs"]:
		var c := o + Vector2(float(a[0]) * s, -float(a[1]) * s)
		var r := float(a[2]) * s
		draw_arc(c, r, deg_to_rad(-float(a[4])), deg_to_rad(-float(a[3])), 28, col, w, true)
		for ang in [float(a[3]), float(a[4])]:
			draw_circle(c + Vector2(cos(deg_to_rad(ang)), -sin(deg_to_rad(ang))) * r, w * 0.5, col)
	if not (l["ellipse"] as Array).is_empty():
		var e: Array = l["ellipse"]
		var c := o + Vector2(float(e[0]) * s, -float(e[1]) * s)
		var pts := PackedVector2Array()
		for k in 49:
			var t := float(k) / 48.0 * TAU
			pts.append(c + Vector2(cos(t) * float(e[2]) * s, -sin(t) * float(e[3]) * s))
		for k in pts.size() - 1:
			draw_line(pts[k], pts[k + 1], col, w, true)
			draw_circle(pts[k], w * 0.5, col)
