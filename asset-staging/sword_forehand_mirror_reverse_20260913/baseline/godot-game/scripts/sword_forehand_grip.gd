extends RefCounted
## Turn the held sword end-for-end while retaining its blade plane and grip.
const MOTION := preload("res://scripts/first_person_motion.gd")
const GRIP := preload("res://scripts/sword_long_grip_visual.gd")


static func angle(phase: String, elapsed: float, _hit_seconds: float, recovery_seconds: float) -> float:
	if phase == "active":
		return PI
	if phase == "recovery" and elapsed < recovery_seconds:
		# Continue to one full turn. Unwinding back to zero would combine with
		# the source recovery into a long turn in the opposite direction.
		return PI * (1.0 + MOTION.smooth_phase(elapsed / maxf(recovery_seconds, 0.000001)))
	return 0.0


static func apply(pose: Transform3D, radians: float) -> Transform3D:
	if radians == 0.0:
		return pose
	var contact := pose * GRIP.GRIP_CENTER
	var basis := pose.basis * Basis(Vector3.BACK, radians)
	return Transform3D(basis, contact - basis * GRIP.GRIP_CENTER)


static func enter(held: Transform3D, authored_contact: Transform3D, progress: float) -> Transform3D:
	# A single shortest rotation from the held blade to the corrected contact.
	# Travel straight into the cut instead of first pulling the grip offscreen.
	var target_basis := authored_contact.basis * Basis(Vector3.BACK, PI)
	var basis := held.basis.slerp(target_basis, clampf(progress, 0.0, 1.0))
	var grip := (held * GRIP.GRIP_CENTER).lerp(authored_contact * GRIP.GRIP_CENTER, clampf(progress, 0.0, 1.0))
	return Transform3D(basis, grip - basis * GRIP.GRIP_CENTER)
