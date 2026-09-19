class_name MovementModel
extends RefCounted
## Pure movement math: takes velocity + bookkeeping + input, returns new velocity + bookkeeping.
## No nodes, no physics server. The body node applies the result with move_and_slide().
## Halo 3 feel: gradual ground acceleration, weak air control, floaty jump, no sprint.


class Result:
	var velocity: Vector3 = Vector3.ZERO
	var jump_buffer: int = 0
	var coyote: int = 0
	var jumped: bool = false


## Forward vector of a body with the given yaw (Godot: -Z is forward at yaw 0).
static func forward_from_yaw(yaw: float) -> Vector3:
	return Vector3(-sin(yaw), 0.0, -cos(yaw))


static func right_from_yaw(yaw: float) -> Vector3:
	return Vector3(cos(yaw), 0.0, -sin(yaw))


## wish: x = strafe (+right), y = forward (+forward), each in [-1, 1], length clamped to 1.
static func step(velocity: Vector3, on_floor: bool, wish: Vector2, yaw: float, jump_pressed: bool,
		jump_buffer: int, coyote: int, dt: float, cfg: MovementConfig) -> Result:
	var r := Result.new()
	var w := wish
	if w.length_squared() > 1.0:
		w = w.normalized()
	var forward := forward_from_yaw(yaw)
	var right := right_from_yaw(yaw)
	var fwd_scale := cfg.backpedal_multiplier if w.y < 0.0 else 1.0
	var wish_vec := right * (w.x * cfg.strafe_multiplier) + forward * (w.y * fwd_scale)
	var target := wish_vec * cfg.walk_speed
	var has_input := w.length_squared() > 0.0001

	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	var vy := velocity.y
	var buffer := jump_buffer
	var coy := coyote

	if on_floor:
		coy = cfg.coyote_ticks
		var accel := cfg.ground_accel if has_input else cfg.ground_decel
		horizontal = horizontal.move_toward(target, accel * dt)
		if vy < 0.0:
			vy = 0.0
	else:
		coy = maxi(0, coy - 1)
		var accel := cfg.air_accel if has_input else cfg.air_decel
		horizontal = horizontal.move_toward(target, accel * dt)
		vy -= cfg.gravity * dt

	buffer = cfg.jump_buffer_ticks if jump_pressed else maxi(0, buffer - 1)
	if buffer > 0 and (on_floor or coy > 0) and vy <= 0.0001:
		vy = cfg.jump_velocity
		buffer = 0
		coy = 0
		r.jumped = true

	r.velocity = Vector3(horizontal.x, vy, horizontal.z)
	r.jump_buffer = buffer
	r.coyote = coy
	return r
