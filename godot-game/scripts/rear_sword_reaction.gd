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
	var twist := smoothstep(MOTION.TWIST_START, MOTION.TWIST_END, elapsed)
	var twist_reaction := sin(PI * twist)
	var withdrawn := smoothstep(MOTION.HOLD_END, MOTION.WITHDRAW_END, elapsed)
	# Contract on insertion, with a second brief involuntary flinch tied to
	# the actual blade roll. The final pose is retained until withdrawal.
	var chest_angle := deg_to_rad(-15.0 * recoil - 3.0 * twist_reaction)
	var head_angle := deg_to_rad(-10.0 * recoil - 6.0 * twist_reaction)
	var chest_twist_angle := deg_to_rad(-8.0 * twist)
	var lateral := actor.global_basis.x.normalized()
	var chest := rig.find_bone("Chest")
	var head := rig.find_bone("Head")
	if chest >= 0 and absf(chest_angle) > .000001:
		# Keep the wound stationary while the straight blade remains embedded.
		var rotation := Basis(Vector3.UP, chest_twist_angle) * Basis(actor.global_basis.z.normalized(), deg_to_rad(-3.0 * twist_reaction)) * Basis(lateral, chest_angle)
		var about_contact := Transform3D(rotation, anchor - rotation * anchor)
		var world_pose := rig.global_transform * rig.get_bone_global_pose(chest)
		rig.set_bone_global_pose(chest, rig.global_transform.affine_inverse() * about_contact * world_pose)
	if head >= 0 and absf(head_angle) > .000001:
		var world_pose := rig.global_transform * rig.get_bone_global_pose(head)
		world_pose.basis = Basis(lateral, head_angle) * world_pose.basis
		rig.set_bone_global_pose(head, rig.global_transform.affine_inverse() * world_pose)
	return {"contact_weight": contact, "penetration_weight": penetration, "recoil_weight": recoil, "withdrawn_weight": withdrawn, "twist_weight": twist, "twist_reaction_weight": twist_reaction, "chest_twist_angle": chest_twist_angle, "chest_angle": chest_angle, "head_angle": head_angle, "exit_right": exit_right, "back_anchor": anchor}
