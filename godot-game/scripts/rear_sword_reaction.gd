extends RefCounted
## A reserved standing pose reacts around the actual back-skin contact. Restore
## the captured local bones before applying this helper; never accumulate it.
const MOTION := preload("res://scripts/rear_takedown_motion.gd")


static func apply(actor: Node3D, rig: Skeleton3D, elapsed: float, anchor: Vector3, exit_right: Vector3) -> Dictionary:
	# React at first surface contact, then contract with the remaining thrust.
	# The old clock waited until the entire blade had already entered.
	var contact := smoothstep(MOTION.STAB_CONTACT, MOTION.STAB_CONTACT + .06, elapsed)
	var penetration := smoothstep(MOTION.STAB_CONTACT, MOTION.STAB_HIT, elapsed)
	var recoil := .25 * contact + .75 * penetration
	var withdrawn := smoothstep(MOTION.HOLD_END, MOTION.WITHDRAW_END, elapsed)
	# A single contact/depth reaction. Keep the final contraction while the
	# blade is held, then release the exact pose to gravity after withdrawal.
	var chest_angle := deg_to_rad(-9.0 * recoil)
	var head_angle := deg_to_rad(-6.0 * recoil)
	var lateral := actor.global_basis.x.normalized()
	var chest := rig.find_bone("Chest")
	var head := rig.find_bone("Head")
	if chest >= 0 and absf(chest_angle) > .000001:
		# Keep the wound stationary while the straight blade remains embedded.
		var rotation := Basis(lateral, chest_angle)
		var about_contact := Transform3D(rotation, anchor - rotation * anchor)
		var world_pose := rig.global_transform * rig.get_bone_global_pose(chest)
		rig.set_bone_global_pose(chest, rig.global_transform.affine_inverse() * about_contact * world_pose)
	if head >= 0 and absf(head_angle) > .000001:
		var world_pose := rig.global_transform * rig.get_bone_global_pose(head)
		world_pose.basis = Basis(lateral, head_angle) * world_pose.basis
		rig.set_bone_global_pose(head, rig.global_transform.affine_inverse() * world_pose)
	return {"contact_weight": contact, "penetration_weight": penetration, "recoil_weight": recoil, "withdrawn_weight": withdrawn, "chest_angle": chest_angle, "head_angle": head_angle, "exit_right": exit_right, "back_anchor": anchor}
