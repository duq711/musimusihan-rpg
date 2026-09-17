extends RigidBody3D
## Detached geometry owns its world transform; the living rig cannot pull it back.
var region := ""
var age := 0.0
var quiet_time := 0.0

func _physics_process(delta: float) -> void:
	age += delta
	if age > 4.0:
		linear_damp = 1.6
		angular_damp = 3.0
	var supported := false
	for body in get_colliding_bodies():
		if body is PhysicsBody3D and body.collision_layer & 2:
			supported = true
	var quiet := linear_velocity.length() < .16 and angular_velocity.length() < .3
	quiet_time = quiet_time + delta if quiet and supported else 0.0
	if quiet_time > .65:
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO
		freeze = true
		set_physics_process(false)
