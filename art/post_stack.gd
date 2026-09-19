class_name PostStack
extends MeshInstance3D
## The post-process stack: ink line work, value ceiling, dither and grain, in one full-screen
## pass drawn on a quad parented to the camera. Post is grading, dither and grain only (STYLE §8).

const SHADER_PATH := "res://art/shaders/outline_post.gdshader"

var material: ShaderMaterial


func setup(map_id: String) -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(2.0, 2.0)
	quad.flip_faces = true
	mesh = quad
	material = ShaderMaterial.new()
	material.shader = load(SHADER_PATH)
	material.set_shader_parameter("ink", Palette.map_colour(map_id, "line"))
	# Lines are drawn at the internal (supersampled) resolution and downsampled with the frame,
	# so their width scales with the render scale and their edges come out anti-aliased.
	var vp := get_viewport()
	var render_scale := vp.scaling_3d_scale if vp != null else float(ProjectSettings.get_setting("rendering/scaling_3d/scale", 1.0))
	material.set_shader_parameter("line_width", 1.7 * render_scale)
	material.set_shader_parameter("value_ceiling", Palette.value_ceiling())
	material_override = material
	extra_cull_margin = 16384.0
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	layers = 1
	position = Vector3(0.0, 0.0, -1.0)


## Keep the line weight in step with the render scale when the player changes it live.
func _process(_delta: float) -> void:
	var vp := get_viewport()
	if vp != null and material != null:
		var want := 1.7 * vp.scaling_3d_scale
		if absf(float(material.get_shader_parameter("line_width")) - want) > 0.01:
			material.set_shader_parameter("line_width", want)


func set_enabled(on: bool) -> void:
	visible = on
