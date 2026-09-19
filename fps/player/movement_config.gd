class_name MovementConfig
extends RefCounted
## Typed view of tuning/movement.json. Cast once here; gameplay never reads raw JSON.

var walk_speed: float = 5.8
var backpedal_multiplier: float = 0.9
var strafe_multiplier: float = 1.0
var ground_accel: float = 40.0
var ground_decel: float = 46.0
var air_accel: float = 9.0
var air_decel: float = 1.5
var gravity: float = 12.5
var jump_velocity: float = 6.1
var jump_buffer_ticks: int = 6
var coyote_ticks: int = 4
var capsule_radius: float = 0.4
var capsule_height: float = 1.8
var eye_height: float = 1.62
var head_radius: float = 0.16
var head_center_height: float = 1.62
var body_capsule_top: float = 1.42
var body_capsule_bottom: float = 0.42
var body_capsule_radius: float = 0.34
var max_slope_deg: float = 46.0
var floor_snap_length: float = 0.3
var fov_vertical: float = 62.0
var pitch_limit_deg: float = 89.0


static func from_dict(d: Dictionary) -> MovementConfig:
	var c := MovementConfig.new()
	c.walk_speed = float(d.get("walk_speed", c.walk_speed))
	c.backpedal_multiplier = float(d.get("backpedal_multiplier", c.backpedal_multiplier))
	c.strafe_multiplier = float(d.get("strafe_multiplier", c.strafe_multiplier))
	c.ground_accel = float(d.get("ground_accel", c.ground_accel))
	c.ground_decel = float(d.get("ground_decel", c.ground_decel))
	c.air_accel = float(d.get("air_accel", c.air_accel))
	c.air_decel = float(d.get("air_decel", c.air_decel))
	c.gravity = float(d.get("gravity", c.gravity))
	c.jump_velocity = float(d.get("jump_velocity", c.jump_velocity))
	c.jump_buffer_ticks = int(d.get("jump_buffer_ticks", c.jump_buffer_ticks))
	c.coyote_ticks = int(d.get("coyote_ticks", c.coyote_ticks))
	c.capsule_radius = float(d.get("capsule_radius", c.capsule_radius))
	c.capsule_height = float(d.get("capsule_height", c.capsule_height))
	c.eye_height = float(d.get("eye_height", c.eye_height))
	c.head_radius = float(d.get("head_radius", c.head_radius))
	c.head_center_height = float(d.get("head_center_height", c.head_center_height))
	c.body_capsule_top = float(d.get("body_capsule_top", c.body_capsule_top))
	c.body_capsule_bottom = float(d.get("body_capsule_bottom", c.body_capsule_bottom))
	c.body_capsule_radius = float(d.get("body_capsule_radius", c.body_capsule_radius))
	c.max_slope_deg = float(d.get("max_slope_deg", c.max_slope_deg))
	c.floor_snap_length = float(d.get("floor_snap_length", c.floor_snap_length))
	c.fov_vertical = float(d.get("fov_vertical", c.fov_vertical))
	c.pitch_limit_deg = float(d.get("pitch_limit_deg", c.pitch_limit_deg))
	return c
