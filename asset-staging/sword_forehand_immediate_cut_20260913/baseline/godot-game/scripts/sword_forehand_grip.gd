extends RefCounted
## Turn the held sword end-for-end while retaining its blade plane and grip.
const MOTION := preload("res://scripts/first_person_motion.gd")
const GRIP := preload("res://scripts/sword_long_grip_visual.gd")


static func angle(phase: String, elapsed: float, hit_seconds: float, recovery_seconds: float) -> float:
	if phase == "active":
		return PI * MOTION.smooth_phase(elapsed / maxf(hit_seconds, 0.000001))
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
