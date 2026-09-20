extends RefCounted
## A reserved standing pose reacts around the actual back-skin contact. Restore
## the captured local bones before applying this helper; never accumulate it.
const MOTION := preload("res://scripts/rear_takedown_motion.gd")


static func apply(actor: Node3D, rig: Skeleton3D, elapsed: float, anchor: Vector3) -> Dictionary:
	var recoil := smoothstep(MOTION.STAB_HIT, MOTION.STAB_HIT + .16, elapsed)
	var withdrawn := smoothstep(MOTION.HOLD_END, MOTION.WITHDRAW_END, elapsed)
	var cut_ready := smoothstep(MOTION.WITHDRAW_END, MOTION.CUT_START, elapsed)
	var chest_angle := deg_to_rad(-9.0 * recoil * (1.0 - .35 * withdrawn))
	var head_angle := deg_to_rad(-6.0 * recoil + 15.0 * cut_ready)
	var lateral := actor.global_basis.x.normalized()
	var chest := rig.find_bone("Chest")
	var head := rig.find_bone("Head")
	if chest >= 0 and absf(chest_angle) > .000001:
		var rotation := Basis(lateral, chest_angle)
		var about_contact := Transform3D(rotation, anchor - rotation * anchor)
		var world_pose := rig.global_transform * rig.get_bone_global_pose(chest)
		rig.set_bone_global_pose(chest, rig.global_transform.affine_inverse() * about_contact * world_pose)
	if head >= 0 and absf(head_angle) > .000001:
		var world_pose := rig.global_transform * rig.get_bone_global_pose(head)
		world_pose.basis = Basis(lateral, head_angle) * world_pose.basis
		rig.set_bone_global_pose(head, rig.global_transform.affine_inverse() * world_pose)
	return {"recoil_weight": recoil, "withdrawn_weight": withdrawn, "cut_ready_weight": cut_ready, "chest_angle": chest_angle, "head_angle": head_angle, "back_anchor": anchor}
