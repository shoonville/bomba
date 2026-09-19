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
	material.set_shader_parameter("value_ceiling", Palette.value_ceiling())
	material_override = material
	extra_cull_margin = 16384.0
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	layers = 1
	position = Vector3(0.0, 0.0, -1.0)


func set_enabled(on: bool) -> void:
	visible = on
