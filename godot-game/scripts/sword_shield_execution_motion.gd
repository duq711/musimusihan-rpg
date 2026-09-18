extends RefCounted
## A paired first-person action: shield press, raised sword, committed cut and
## withdrawal. The gameplay clock owns contact; rendering never deals damage.
const POSE := preload("res://scripts/sword_shield_choreography.gd")
const HIT_SECONDS := 0.82
const DURATION := 1.55
const CHARGE_SECONDS := 0.40
const MAX_DISTANCE := 2.20
const CONTACT_DISTANCE := 1.25
const STAMINA_COST := 25.0


static func phase(elapsed: float) -> String:
	if elapsed < 0.30: return "방패 밀치기"
	if elapsed < 0.66: return "검 들어올리기"
	if elapsed < HIT_SECONDS: return "처형 내려베기"
	if elapsed < 1.02: return "결정타"
	return "검·방패 회수"


static func sword(elapsed: float, entry: Transform3D) -> Transform3D:
	var chamber := POSE.held(Vector3(0.35, -0.13, -0.41), Vector3(0.06, 0.97, -0.23), 12.0)
	var raised := POSE.held(Vector3(0.28, 0.12, -0.35), Vector3(-0.20, 0.95, 0.24), 8.0)
	var contact := POSE.held(Vector3(0.14, -0.10, -0.57), Vector3(-0.09, -0.48, -0.87), 5.0)
	var follow := POSE.held(Vector3(0.09, -0.36, -0.55), Vector3(-0.22, -0.73, -0.65), 2.0)
	var withdrawn := POSE.held(Vector3(0.43, -0.28, -0.39), Vector3(0.65, 0.35, -0.67), 12.0)
	if elapsed < 0.30: return POSE.mix(entry, chamber, elapsed / 0.30)
	if elapsed < 0.66: return POSE.mix(chamber, raised, (elapsed - 0.30) / 0.36)
	if elapsed < HIT_SECONDS: return POSE.mix(raised, contact, (elapsed - 0.66) / (HIT_SECONDS - 0.66))
	# Brief resistance at contact, then the blade continues down and outward.
	if elapsed < 0.87: return contact
	if elapsed < 1.02: return POSE.mix(contact, follow, (elapsed - 0.87) / 0.15)
	if elapsed < 1.23: return POSE.mix(follow, withdrawn, (elapsed - 1.02) / 0.21)
	return POSE.mix(withdrawn, POSE.ready(), (elapsed - 1.23) / (DURATION - 1.23))


static func shield(elapsed: float, entry: Transform3D, rest: Transform3D) -> Transform3D:
	# The left hand remains on the shield throughout, leaving the centre open.
	var braced := POSE.pose(Vector3(-0.30, -0.40, -0.58), Vector3(9.0, 24.0, -8.0))
	var pressed := POSE.pose(Vector3(-0.24, -0.31, -0.84), Vector3(2.0, 17.0, -12.0))
	var held := POSE.pose(Vector3(-0.37, -0.37, -0.69), Vector3(6.0, 28.0, -14.0))
	if elapsed < 0.13: return POSE.mix(entry, braced, elapsed / 0.13)
	if elapsed < 0.25: return POSE.mix(braced, pressed, (elapsed - 0.13) / 0.12)
	if elapsed < 0.42: return POSE.mix(pressed, held, (elapsed - 0.25) / 0.17)
	if elapsed < 1.02: return held
	return POSE.mix(held, rest, (elapsed - 1.02) / (DURATION - 1.02))


static func camera_offset(elapsed: float) -> Vector3:
	var step := sin(PI * clampf(elapsed / 0.42, 0.0, 1.0))
	var impact := maxf(0.0, 1.0 - absf(elapsed - HIT_SECONDS) / 0.10)
	return Vector3(0.0, -0.018 * step - 0.012 * impact, -0.035 * step)


static func camera_rotation(elapsed: float) -> Vector3:
	var weight := sin(PI * clampf((elapsed - 0.58) / 0.58, 0.0, 1.0))
	return Vector3(-0.025, 0.0, -0.012) * weight
