extends RefCounted
## A reserved standing pose reacts around the actual back-skin contact. Restore
## the captured local bones before applying this helper; never accumulate it.
const MOTION := preload("res://scripts/rear_takedown_motion.gd")


static func apply(actor: Node3D, rig: Skeleton3D, elapsed: float, anchor: Vector3, exit_left: Vector3) -> Dictionary:
	var recoil := smoothstep(MOTION.STAB_HIT, MOTION.STAB_HIT + .16, elapsed)
	var withdrawn := smoothstep(MOTION.HOLD_END, MOTION.WITHDRAW_END, elapsed)
	var lateral_exit := smoothstep(MOTION.CUT_START, MOTION.CUT_HIT, elapsed)
	var chest_angle := deg_to_rad(-9.0 * recoil - 4.0 * lateral_exit)
	var head_angle := deg_to_rad(-6.0 * recoil - 3.0 * lateral_exit)
	var side_angle := deg_to_rad(9.0 * lateral_exit)
	var twist_angle := deg_to_rad(7.0 * lateral_exit)
	var lateral := actor.global_basis.x.normalized()
	var tilt_axis := Vector3.UP.cross(exit_left).normalized()
	var chest := rig.find_bone("Chest")
	var head := rig.find_bone("Head")
	if chest >= 0 and absf(chest_angle) > .000001:
		# Keep the entry wound anchored while embedded. At lateral extraction,
		# contract and follow the pull instead of lifting the head for a neck cut.
		var rotation := Basis(Vector3.UP, twist_angle) * Basis(tilt_axis, side_angle) * Basis(lateral, chest_angle)
		var about_contact := Transform3D(rotation, anchor - rotation * anchor)
		var world_pose := rig.global_transform * rig.get_bone_global_pose(chest)
		rig.set_bone_global_pose(chest, rig.global_transform.affine_inverse() * about_contact * world_pose)
	if head >= 0 and absf(head_angle) > .000001:
		var world_pose := rig.global_transform * rig.get_bone_global_pose(head)
		world_pose.basis = Basis(lateral, head_angle) * world_pose.basis
		rig.set_bone_global_pose(head, rig.global_transform.affine_inverse() * world_pose)
	return {"recoil_weight": recoil, "withdrawn_weight": withdrawn, "lateral_exit_weight": lateral_exit, "chest_angle": chest_angle, "head_angle": head_angle, "side_angle": side_angle, "twist_angle": twist_angle, "exit_left": exit_left, "back_anchor": anchor}
