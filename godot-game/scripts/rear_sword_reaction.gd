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
	# Extend through the neck as well as the skull. The old negative pitch
	# bowed the face down precisely when the stab should lift it in a cry.
	var head_lift := recoil
	var neck_angle := deg_to_rad(26.0 * head_lift + 2.0 * twist_reaction)
	var head_angle := deg_to_rad(48.0 * head_lift + 3.0 * twist_reaction)
	var chest_twist_angle := deg_to_rad(-8.0 * twist)
	var lateral := actor.global_basis.x.normalized()
	var chest := rig.find_bone("Chest")
	var head := rig.find_bone("Head")
	var neck := rig.find_bone("Neck")
	var jaw := rig.find_bone("Jaw2")
	var jaw_angle := deg_to_rad(24.0 * head_lift + 2.0 * twist_reaction)
	if chest >= 0 and absf(chest_angle) > .000001:
		# Keep the wound stationary while the straight blade remains embedded.
		var rotation := Basis(Vector3.UP, chest_twist_angle) * Basis(actor.global_basis.z.normalized(), deg_to_rad(-3.0 * twist_reaction)) * Basis(lateral, chest_angle)
		var about_contact := Transform3D(rotation, anchor - rotation * anchor)
		var world_pose := rig.global_transform * rig.get_bone_global_pose(chest)
		rig.set_bone_global_pose(chest, rig.global_transform.affine_inverse() * about_contact * world_pose)
	if neck >= 0 and absf(neck_angle) > .000001:
		var world_pose := rig.global_transform * rig.get_bone_global_pose(neck)
		world_pose.basis = Basis(lateral, neck_angle) * world_pose.basis
		rig.set_bone_global_pose(neck, rig.global_transform.affine_inverse() * world_pose)
	if head >= 0 and absf(head_angle) > .000001:
		var world_pose := rig.global_transform * rig.get_bone_global_pose(head)
		world_pose.basis = Basis(lateral, head_angle) * world_pose.basis
		rig.set_bone_global_pose(head, rig.global_transform.affine_inverse() * world_pose)
	if jaw >= 0 and jaw_angle > .000001:
		# The installed Creep's authored roar opens lower-jaw Jaw2 by about
		# +24 degrees on its local X axis. Keep the original upper jaw/teeth.
		var pose := rig.get_bone_pose(jaw)
		pose.basis = pose.basis * Basis(Vector3.RIGHT, jaw_angle)
		rig.set_bone_pose(jaw, pose)
	return {"contact_weight": contact, "penetration_weight": penetration, "recoil_weight": recoil, "withdrawn_weight": withdrawn, "twist_weight": twist, "twist_reaction_weight": twist_reaction, "chest_twist_angle": chest_twist_angle, "chest_angle": chest_angle, "head_angle": head_angle, "neck_angle": neck_angle, "jaw_angle": jaw_angle, "head_lift_weight": head_lift, "exit_right": exit_right, "back_anchor": anchor}
