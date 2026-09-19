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


static func for_tone(map_id: String, tone: String) -> ShaderMaterial:
	var key := "%s/%s" % [map_id, tone]
	if _cache.has(key):
		return _cache[key]
	var palette_key := tone
	if tone == "floor":
		palette_key = "field_dark"
	var colour := Palette.map_colour(map_id, palette_key)
	if tone == "floor":
		colour = Color.from_hsv(colour.h, colour.s * 0.8, colour.v * 0.92)
	var m := for_colour(colour, Palette.map_colour(map_id, "shadow_tint"))
	_cache[key] = m
	return m
