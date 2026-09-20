extends RefCounted
## A reserved standing pose reacts around the actual back-skin contact. Restore
## the captured local bones before applying this helper; never accumulate it.
const MOTION := preload("res://scripts/rear_takedown_motion.gd")


static func apply(actor: Node3D, rig: Skeleton3D, elapsed: float, anchor: Vector3, exit_right: Vector3) -> Dictionary:
	var recoil := smoothstep(MOTION.STAB_HIT, MOTION.STAB_HIT + .16, elapsed)
	var withdrawn := smoothstep(MOTION.HOLD_END, MOTION.WITHDRAW_END, elapsed)
	# The blade turns only after the deep stab. A single restrained contraction
	# follows that turn, then the body follows the rightward extraction.
	var blade_twist := smoothstep(MOTION.TWIST_START, MOTION.TWIST_END, elapsed)
	var twist_recoil := sin(PI * blade_twist)
	var lateral_exit := smoothstep(MOTION.CUT_START, MOTION.CUT_HIT, elapsed)
	var chest_angle := deg_to_rad(-9.0 * recoil - 3.0 * twist_recoil - 4.0 * lateral_exit)
	var head_angle := deg_to_rad(-6.0 * recoil - 2.0 * twist_recoil - 3.0 * lateral_exit)
	var side_angle := deg_to_rad(2.0 * twist_recoil + 9.0 * lateral_exit)
	var twist_angle := deg_to_rad(-4.0 * twist_recoil - 7.0 * lateral_exit)
	var lateral := actor.global_basis.x.normalized()
	var tilt_axis := Vector3.UP.cross(exit_right).normalized()
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
	return {"recoil_weight": recoil, "withdrawn_weight": withdrawn, "lateral_exit_weight": lateral_exit, "blade_twist_weight": blade_twist, "twist_recoil_weight": twist_recoil, "chest_angle": chest_angle, "head_angle": head_angle, "side_angle": side_angle, "twist_angle": twist_angle, "exit_right": exit_right, "back_anchor": anchor}
