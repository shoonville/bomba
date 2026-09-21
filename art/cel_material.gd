class_name CelMaterial
extends RefCounted
## Makes cel ShaderMaterials from palette entries. One shader, many colours.

const SHADER_PATH := "res://art/shaders/cel.gdshader"

static var _shader: Shader
static var _cache: Dictionary = {}


static func shader() -> Shader:
	if _shader == null:
		_shader = load(SHADER_PATH)
	return _shader


const VIEWMODEL_SHADER_PATH := "res://art/shaders/cel_viewmodel.gdshader"

static var _viewmodel_shader: Shader


static func viewmodel_shader() -> Shader:
	if _viewmodel_shader == null:
		_viewmodel_shader = load(VIEWMODEL_SHADER_PATH)
	return _viewmodel_shader


static func for_colour(colour: Color, shadow_tint: Color = Color(0.66, 0.70, 0.86), emission: float = 0.0, viewmodel: bool = false) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = viewmodel_shader() if viewmodel else shader()
	m.set_shader_parameter("albedo", Palette.under_ceiling(colour))
	m.set_shader_parameter("shadow_tint", shadow_tint)
	m.set_shader_parameter("emission_strength", emission)
	m.set_shader_parameter("emission_color", colour)
	return m


## A map tone's material, cached. `print_kind` ("floor", "wall", "moon", ...) adds the print layer
## from tuning/palette.json "print" in the map's ink; big flat surfaces ask for it, props do not.
static func for_tone(map_id: String, tone: String, print_kind: String = "") -> ShaderMaterial:
	var key := "%s/%s/%s" % [map_id, tone, print_kind]
	if _cache.has(key):
		return _cache[key]
	var palette_key := tone
	if tone == "floor":
		palette_key = "field_dark"
	var colour := Palette.map_colour(map_id, palette_key)
	if tone == "floor":
		colour = Color.from_hsv(colour.h, colour.s * 0.8, colour.v * 0.92)
	var m := for_colour(colour, Palette.map_colour(map_id, "shadow_tint"))
	if print_kind != "":
		with_print(m, print_kind, Palette.map_colour(map_id, "line"))
	_cache[key] = m
	return m


## The print layer (STYLE.md §3: interior line work; §8: silhouette-only outlines read as generic
## toon shading): world-space ink seams with a flat value step per cell, and hard-edged mottle
## blotches, from tuning/palette.json "print" by kind. Nothing changes for a kind that is not there.
static func with_print(m: ShaderMaterial, kind: String, ink: Color) -> ShaderMaterial:
	var p: Dictionary = Tuning.value("palette.print.%s" % kind, {})
	if p.is_empty():
		return m
	var seam: Array = p.get("seam", [0.0, 0.0])
	m.set_shader_parameter("seam_size", Vector2(float(seam[0]), float(seam[1])))
	m.set_shader_parameter("seam_width", float(p.get("width", 0.05)))
	m.set_shader_parameter("seam_strength", float(p.get("strength", 0.85)))
	m.set_shader_parameter("seam_ink", ink)
	m.set_shader_parameter("seam_base_y", float(p.get("base_y", 0.0)))
	m.set_shader_parameter("cell_jitter", float(p.get("jitter", 0.0)))
	m.set_shader_parameter("mottle_size", float(p.get("mottle", 0.0)))
	m.set_shader_parameter("mottle_strength", float(p.get("mottle_strength", 0.0)))
	m.set_shader_parameter("mottle_threshold", float(p.get("mottle_threshold", 0.55)))
	return m
