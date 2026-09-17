extends RefCounted
class_name SwordShieldChoreography
## Authored hand-driven actions. Coordinates are in the first-person camera's
## frame; +Y is up, -Z faces the opponent. Weapons remain rigid in the hands.

const VARIANTS := ["right_diagonal", "left_reverse", "overhead"]
const RAISE_SECONDS := 0.24
const LOWER_SECONDS := 0.30
const IMPACT_SECONDS := 0.30
const PALM := Vector3(0, -0.0275, -0.0925)
const SWORD_GRIP := Vector3(0, -0.108, 0.002)

static func smooth(t: float) -> float:
	var x := clampf(t, 0, 1)
	return x * x * (3.0 - 2.0 * x)

static func mix(a: Transform3D, b: Transform3D, t: float) -> Transform3D:
	return a.interpolate_with(b, smooth(t))

static func pose(p: Vector3, degrees: Vector3) -> Transform3D:
	return Transform3D(Basis.from_euler(degrees * PI / 180.0), p)

static func held(palm: Vector3, tip_direction: Vector3, roll_degrees := 0.0) -> Transform3D:
	var y := tip_direction.normalized()
	var z := Vector3.BACK - y * y.dot(Vector3.BACK)
	if z.length_squared() < 0.001: z = Vector3.UP - y * y.dot(Vector3.UP)
	z = z.normalized().rotated(y, deg_to_rad(roll_degrees))
	var basis := Basis(y.cross(z).normalized(), y, z)
	return Transform3D(basis, palm - basis * SWORD_GRIP)

static func ready() -> Transform3D:
	return pose(Vector3(0.57, -0.285, -0.75), Vector3(-18.93, -24.44, 13.59))

static func keys(variant: String, charge: float) -> Array[Transform3D]:
	var windup: Transform3D
	var contact: Transform3D
	var follow: Transform3D
	match variant:
		"left_reverse":
			windup = held(Vector3(-0.12,-0.15,-0.40), Vector3(-0.30,0.91,0.28), -25)
			contact = held(Vector3(0.19,-0.23,-0.65), Vector3(0.66,0.35,-0.66), -35)
			follow = held(Vector3(0.40,-0.055,-0.56), Vector3(0.62,0.73,-0.28), -15)
		"overhead":
			windup = held(Vector3(0.26,0.14,-0.38), Vector3(-0.80,0.55,0.24), 5)
			contact = held(Vector3(0.19,0.01,-0.57), Vector3(-0.08,-0.65,-0.76), 0)
			follow = held(Vector3(0.19,-0.26,-0.61), Vector3(-0.03,-0.82,-0.57), 0)
		_:
			windup = held(Vector3(0.35,0.055,-0.53), Vector3(-0.40,0.83,0.38), 20)
			contact = held(Vector3(0.20,-0.20,-0.65), Vector3(-0.72,-0.20,-0.66453), 25)
			follow = held(Vector3(0.14,-0.25,-0.57), Vector3(-0.91,-0.34,-0.24), 20)
	windup.origin += Vector3(0,0.025,0.018) * clampf(charge,0,1)
	return [windup, contact, follow]

static func sword(phase: String, elapsed: float, charge: float, variant: String) -> Transform3D:
	var points := keys(variant,charge)
	match phase:
		"windup": return mix(ready(),points[0],elapsed / 0.22)
		"active":
			# Keep the real 55ms hit checkpoint. The latter half of the sweep
			# decelerates into recovery, instead of reversing at active-end.
			if elapsed <= 0.055:
				var crossing := points[1]
				crossing.origin += Vector3(0.004,0.004,0.004)
				if variant == "right_diagonal": crossing = held(Vector3(0.20,-0.20,-0.65),Vector3(-0.76,-0.18,-0.6244998),25)
				return mix(points[0],crossing,elapsed / 0.05) if elapsed <= 0.05 else mix(crossing,points[1],(elapsed - 0.05) / 0.005)
			return mix(points[1],points[2],(elapsed - 0.055) / 0.185)
		"recovery":
			if elapsed < 0.08: return mix(points[1],points[2],(0.105 + elapsed) / 0.185)
			var recovery_t := (elapsed - 0.08) / (lerpf(0.47,0.68,charge) - 0.08)
			if variant == "overhead":
				var withdrawn := held(Vector3(0.40,-0.22,-0.58),Vector3(0.84,0.15,-0.52),20)
				return mix(points[2],withdrawn,recovery_t / 0.5) if recovery_t < 0.5 else mix(withdrawn,ready(),(recovery_t - 0.5) / 0.5)
			return mix(points[2],ready(),recovery_t)
		"guard_break": return mix(pose(Vector3(0.48,-0.50,-0.53),Vector3(-3,10,-61)),ready(),elapsed / 1.05)
	return ready()

static func attack_weight(phase: String, elapsed: float, charge: float) -> float:
	if phase == "windup": return smooth(elapsed / 0.22)
	if phase == "active": return 1.0
	if phase == "recovery": return 1.0 - smooth(elapsed / lerpf(0.47,0.68,charge))
	return 0.0

static func wrist_roll(phase: String, elapsed: float, charge: float, variant: String) -> float:
	# Present a readable three-quarter fist. Counter the forearm's natural
	# axial turn during the cut, then unwind through the existing recovery.
	var preparation := 0.0 if variant == "left_reverse" else -20.0
	var cutting := -20.0 if variant == "left_reverse" else (15.0 if variant == "overhead" else 20.0)
	if phase == "windup": return lerpf(-20.0,preparation,smooth(elapsed / 0.22))
	if phase == "active": return lerpf(preparation,cutting,smooth(elapsed / 0.055))
	if phase == "recovery": return lerpf(cutting,-20.0,smooth(elapsed / lerpf(0.47,0.68,charge)))
	return -20.0

static func guard_sword(raise_progress: float) -> Transform3D:
	return mix(ready(),pose(Vector3(0.56,-0.26,-0.74),Vector3(-15,-28,11)),raise_progress)

static func recoil(remaining: float) -> float:
	var elapsed := IMPACT_SECONDS - clampf(remaining,0,IMPACT_SECONDS)
	# 55ms compression, 245ms controlled rebound; zero position/velocity at ends.
	return smooth(elapsed / 0.055) if elapsed < 0.055 else 1.0 - smooth((elapsed - 0.055) / 0.245)

static func shield(raise_progress: float, impact_remaining: float, phase: String, elapsed: float, charge: float, variant: String) -> Transform3D:
	var idle := pose(Vector3(-0.38,-0.46,-0.47),Vector3(-19.28,83.44,20))
	var guard := pose(Vector3(-0.27,-0.12,-0.49),Vector3(24.62,66.04,20))
	var flank := pose(Vector3(-0.58,-0.46,-0.34),Vector3(-10,75,-28))
	if variant == "left_reverse": flank = pose(Vector3(-0.53,-0.59,-0.32),Vector3(-25,74,-39))
	if variant == "overhead": flank = pose(Vector3(-0.47,-0.38,-0.40),Vector3(3,72,-19))
	var result := mix(mix(idle,flank,attack_weight(phase,elapsed,charge)),guard,raise_progress)
	var pulse := recoil(impact_remaining) if impact_remaining > 0.0 else 0.0
	result.origin += Vector3(-0.055,-0.035,0.105) * pulse
	result.basis = result.basis * Basis.from_euler(Vector3(-0.10,0.08,-0.065) * pulse)
	return result

static func elbow(shoulder: Vector3, wrist: Vector3, pole: Vector3, upper := 0.36, forearm := 0.34) -> Vector3:
	var offset := wrist - shoulder
	var distance := maxf(0.001,offset.length())
	var axis := offset / distance
	var reach := minf(distance,upper + forearm - 0.002)
	var along := (upper * upper - forearm * forearm + reach * reach) / (2.0 * reach)
	var height := sqrt(maxf(0.0001,upper * upper - along * along))
	var bend := pole - axis * pole.dot(axis)
	if bend.length_squared() < 0.00001: bend = Vector3.RIGHT - axis * axis.x
	return shoulder + axis * along + bend.normalized() * height
