extends RefCounted
## A short impact contraction around the stab point. Navigation, pelvis and
## severed branches retain the reserved prone pose; no standing clip is played.
const MOTION := preload("res://scripts/creep_execution_motion.gd")


static func weights(elapsed: float) -> Vector2:
	return Vector2(
		_pulse(elapsed - MOTION.FIRST_IMPACT_SECONDS, .045, .20),
		_pulse(elapsed - (MOTION.HIT_SECONDS - .09), .09, .22))


static func _pulse(time: float, rise: float, fall: float) -> float:
	if time <= 0.0 or time >= rise + fall: return 0.0
	if time < rise: return smoothstep(0.0, rise, time)
	return 1.0 - smoothstep(rise, rise + fall, time)


static func apply(actor: Node3D, rig: Skeleton3D, elapsed: float, anchor: Vector3) -> Dictionary:
	var weight := weights(elapsed)
	var chest_angle := deg_to_rad(6.0 * weight.x + 8.0 * weight.y)
	var head_angle := deg_to_rad(9.0 * weight.x + 12.0 * weight.y)
	var lateral := actor.global_basis.x.normalized()
	var chest := rig.find_bone("Chest")
	var head := rig.find_bone("Head")
	if chest >= 0 and chest_angle > 0.000001:
		var rotation := Basis(lateral, chest_angle)
		var around_contact := Transform3D(rotation, anchor - rotation * anchor)
		var world_pose := rig.global_transform * rig.get_bone_global_pose(chest)
		rig.set_bone_global_pose(chest, rig.global_transform.affine_inverse() * around_contact * world_pose)
	if head >= 0 and head_angle > 0.000001:
		var world_pose := rig.global_transform * rig.get_bone_global_pose(head)
		world_pose.basis = Basis(lateral, head_angle) * world_pose.basis
		rig.set_bone_global_pose(head, rig.global_transform.affine_inverse() * world_pose)
	return {"first_weight": weight.x, "deep_weight": weight.y, "chest_angle": chest_angle, "head_angle": head_angle, "contact_anchor": anchor}
