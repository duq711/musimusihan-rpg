extends RefCounted
## One continuous short thrust; +Y is the physical dagger's blade axis.
const WINDUP_SECONDS := 0.10
const HIT_SECONDS := 0.13
const ACTIVE_SECONDS := 0.30
const RECOVERY_SECONDS := 0.25

static func _frame(position: Vector3, angles: Vector3) -> Transform3D:
	return Transform3D(Basis.from_euler(angles), position)

static func _ease(value: float) -> float:
	var t := clampf(value, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)

static func pose(phase: String, seconds: float, blocking: bool = false) -> Transform3D:
	var ready := _frame(Vector3(.25, -.28, -.48), Vector3(-1.10, 0, -.15))
	var prepared := _frame(Vector3(.31, -.24, -.39), Vector3(-1.15, .10, -.10))
	var contact := _frame(Vector3(.015, -.025, -.73), Vector3(-PI * .5, 0, .03))
	var withdrawn := contact.interpolate_with(ready, .45)
	match phase:
		"windup": return ready.interpolate_with(prepared, _ease(seconds / WINDUP_SECONDS))
		"active":
			if seconds <= HIT_SECONDS:
				return prepared.interpolate_with(contact, _ease(seconds / HIT_SECONDS))
			return contact.interpolate_with(withdrawn, _ease((seconds - .18) / (ACTIVE_SECONDS - .18)))
		"recovery": return withdrawn.interpolate_with(ready, _ease(seconds / RECOVERY_SECONDS))
	if blocking:
		ready.origin += Vector3(.06, -.08, .06)
	return ready
