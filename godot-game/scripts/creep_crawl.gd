extends Node
## Grounded locomotion after either leg is lost. Source prone pose supplies the
## spine/remaining leg anatomy; independent hand roots are solved explicitly.
const ENTER_SECONDS := .48
const STRIDE := .62
const STANCE := .64
var actor: Node3D
var rig: Skeleton3D
var active := false
var blend := 0.0
var phase := 0.0
var prone: Array[Transform3D] = []
var upright: Array[Transform3D] = []
var entry: Array[Transform3D] = []
var order: Array[int] = []
var last_position := Vector3.ZERO
var hand_targets := {}
var planted := {}
var movement_blend := 0.0
var entry_seconds := ENTER_SECONDS
var foot_targets := {}

func _lower_body(poses: Array[Transform3D], body_basis: Basis) -> void:
	var pelvis := rig.find_bone("Torso")
	var chest := rig.find_bone("Chest")
	var supported_chest := poses[chest]
	var cycle := phase * TAU
	var sway := sin(cycle) * movement_blend
	var pull := sin(cycle * 2.0) * movement_blend
	var pelvis_origin := poses[pelvis].origin + Vector3(.045 * sway, .012 * (1.0 - cos(cycle * 2.0)) * movement_blend, .025 * pull)
	# Unroll the sleeping pelvis onto its belly. Hip spacing comes from the
	# original rig; the chest stays supported while the pelvis twists below it.
	var pelvis_basis := body_basis * Basis(Vector3.UP, .14 * sway) * Basis(Vector3.FORWARD, .07 * sway) * Basis(Vector3.RIGHT, -PI * .5 + .045 * pull) * upright[pelvis].basis
	_branch(poses, pelvis, Transform3D(pelvis_basis, pelvis_origin))
	_branch(poses, chest, supported_chest)
	foot_targets.clear()
	for side: String in ["L", "R"]:
		var region := "left_leg" if side == "L" else "right_leg"
		if region in actor.dismemberment.severed:
			continue
		# The remaining leg helps the opposite hand: plant/push, then draw the
		# bent knee forward and drag the toes back into position near the floor.
		var p := fposmod(phase + (.5 if side == "L" else 0.0), 1.0)
		var stance := .70
		var foot_z := .68 + STRIDE * p if p < stance else lerpf(.68 + STRIDE * stance, .68, smoothstep(stance, 1.0, p))
		var lift := sin((p - stance) / (1.0 - stance) * PI) * .045 if p >= stance else 0.0
		# The source foot flesh extends about 13cm below its ankle joint.
		var target := Vector3(-.36 if side == "L" else .36, -.76 + lift * movement_blend, lerpf(.88, foot_z, movement_blend))
		_leg(poses, side, target)
		foot_targets[side] = actor.global_transform * poses[rig.find_bone("Foot." + side)].origin

func _leg(poses: Array[Transform3D], side: String, foot_target: Vector3) -> void:
	var upper := rig.find_bone("Leg1." + side)
	var lower := rig.find_bone("Leg2." + side)
	var hock := rig.find_bone("Leg3." + side)
	var foot := rig.find_bone("Foot." + side)
	var hip := poses[upper].origin
	var a := upright[upper].origin.distance_to(upright[lower].origin)
	var b := upright[lower].origin.distance_to(upright[hock].origin)
	var c := upright[hock].origin.distance_to(upright[foot].origin)
	var lateral := -1.0 if side == "L" else 1.0
	var ankle_offset := Vector3(lateral * .025, .16, -sqrt(c * c - .16 * .16 - .025 * .025))
	var ankle := foot_target + ankle_offset
	var reach := clampf(hip.distance_to(ankle), absf(a - b) + .005, a + b - .01)
	var direction := hip.direction_to(ankle)
	# Keep the knee outside the belly, bending in the plane of travel.
	var pole := Vector3(lateral, .04, -.45)
	pole = (pole - direction * pole.dot(direction)).normalized()
	var along := (a * a - b * b + reach * reach) / (2.0 * reach)
	var knee := hip + direction * along + pole * sqrt(maxf(0.0, a * a - along * along))
	ankle = hip + direction * reach
	foot_target = ankle - ankle_offset
	var old_hock := upright[hock]
	var old_ankle_direction := old_hock.origin.direction_to(upright[foot].origin)
	_aim(poses, upper, lower, hip, knee)
	_aim(poses, lower, hock, knee, ankle)
	_branch(poses, hock, Transform3D(Basis(Quaternion(old_ankle_direction, ankle.direction_to(foot_target))) * old_hock.basis, ankle))
	# Foot is a separate imported IK root. Move its complete toe hierarchy to
	# the solved ankle, with relaxed toes trailing behind the crawling body.
	_branch(poses, foot, Transform3D(Basis(Vector3.UP, PI) * upright[foot].basis, foot_target))

func begin_from_world_pose(world_poses: Array) -> void:
	assert(world_poses.size() == rig.get_bone_count())
	entry.clear()
	var to_actor := actor.global_transform.affine_inverse()
	for pose: Transform3D in world_poses:
		entry.append(to_actor * pose)
	active = true
	blend = 0.0
	phase = 0.0
	movement_blend = 0.0
	entry_seconds = .85
	last_position = actor.global_position
	apply(0.0)

func configure(owner_actor: Node3D, skeleton: Skeleton3D) -> void:
	actor = owner_actor
	rig = skeleton
	actor.animation_player.play("idle")
	actor.animation_player.seek(0.0, true)
	upright = _capture()
	actor.animation_player.play("sleep") # Godot imports source sleep_loop as sleep.
	actor.animation_player.seek(1.2, true)
	prone = _capture()
	# Centre the source sleeping pose under the navigation body and face forward.
	var hip := prone[rig.find_bone("Torso")].origin
	var chest := prone[rig.find_bone("Chest")].origin
	var forward := chest - hip
	forward.y = 0
	var yaw := Basis(Quaternion(forward.normalized(), Vector3.FORWARD))
	var recenter := Transform3D(yaw, Vector3(0, 0, .30) - yaw * Vector3(hip.x, 0, hip.z))
	for bone in prone.size():
		prone[bone] = recenter * prone[bone]
		order.append(bone)
	order.sort_custom(func(a: int, b: int): return _depth(a) < _depth(b))
	actor.animation_player.play("idle")
	actor.animation_player.seek(0.0, true)

func _capture() -> Array[Transform3D]:
	var result: Array[Transform3D] = []
	var to_actor: Transform3D = actor.global_transform.affine_inverse() * rig.global_transform
	for bone in rig.get_bone_count():
		result.append(to_actor * rig.get_bone_global_pose(bone))
	return result

func _depth(bone: int) -> int:
	var depth := 0
	while rig.get_bone_parent(bone) >= 0:
		bone = rig.get_bone_parent(bone)
		depth += 1
	return depth

func _branch(poses: Array[Transform3D], bone: int, pose: Transform3D) -> void:
	var change := pose * poses[bone].affine_inverse()
	for candidate in poses.size():
		var ancestor := candidate
		while ancestor >= 0:
			if ancestor == bone:
				poses[candidate] = change * poses[candidate]
				break
			ancestor = rig.get_bone_parent(ancestor)

func _aim(poses: Array[Transform3D], bone: int, child: int, origin: Vector3, endpoint: Vector3) -> void:
	var direction := (poses[child].origin - poses[bone].origin).normalized()
	var rotation := Basis(Quaternion(direction, origin.direction_to(endpoint)))
	_branch(poses, bone, Transform3D(rotation * poses[bone].basis, origin))

func _arm(poses: Array[Transform3D], side: String, target: Vector3) -> void:
	var upper := rig.find_bone("Arm1." + side)
	var lower := rig.find_bone("Arm2." + side)
	var hand := rig.find_bone("Hand." + side)
	var finger := rig.find_bone("FingB1." + side)
	var shoulder := poses[upper].origin
	var a := upright[upper].origin.distance_to(upright[lower].origin)
	var b := upright[lower].origin.distance_to(upright[hand].origin)
	var reach := clampf(shoulder.distance_to(target), absf(a - b) + .005, a + b - .01)
	var direction := shoulder.direction_to(target)
	target = shoulder + direction * reach
	var along := (a * a - b * b + reach * reach) / (2.0 * reach)
	var pole := Vector3(-1 if side == "L" else 1, .28, .1)
	pole = (pole - direction * pole.dot(direction)).normalized()
	var elbow := shoulder + direction * along + pole * sqrt(maxf(0.0, a * a - along * along))
	var original_lower := poses[lower]
	var original_forearm := original_lower.origin.direction_to(poses[hand].origin)
	_aim(poses, upper, lower, shoulder, elbow)
	_branch(poses, lower, Transform3D(Basis(Quaternion(original_forearm, elbow.direction_to(target))) * original_lower.basis, elbow))
	# Hand is an independent IK root, with fingers parented below it.
	# Flatten the palm/finger direction rather than leave claws pointing down.
	var finger_direction := (poses[finger].origin - poses[hand].origin).normalized()
	var hand_rotation := Basis(Quaternion(finger_direction, Vector3(0, .08, -1).normalized()))
	_branch(poses, hand, Transform3D(hand_rotation * poses[hand].basis, target))

func apply(delta: float) -> void:
	if not active:
		entry = _capture()
		active = true
		last_position = actor.global_position
	var displacement := actor.global_position - last_position
	displacement.y = 0
	last_position = actor.global_position
	blend = minf(1.0, blend + maxf(delta, 0.0) / entry_seconds)
	var recovering: bool = actor.is_knocked_down()
	var moving: bool = not recovering and actor.ai_state == DungeonEnemy.AIState.CHASE and displacement.length() > .00001
	movement_blend = move_toward(movement_blend, 1.0 if moving else 0.0, maxf(delta, 0.0) * 4.5)
	if moving:
		phase = fposmod(phase + displacement.length() / STRIDE, 1.0)
	var poses: Array[Transform3D] = prone.duplicate()
	var biting: bool = not recovering and actor.ai_state in [DungeonEnemy.AIState.WINDUP, DungeonEnemy.AIState.ACTIVE, DungeonEnemy.AIState.RECOVERY]
	var t: float = actor.state_time
	if actor.ai_state == DungeonEnemy.AIState.ACTIVE: t += actor.WINDUPS[0]
	if actor.ai_state == DungeonEnemy.AIState.RECOVERY: t += actor.WINDUPS[0] + actor.ACTIVE_TIMES[0]
	var lunge := (smoothstep(.60, 1.0, t) * (1.0 - smoothstep(1.04, 1.60, t))) if biting else 0.0
	var recoil := sin(clampf(actor.state_time / maxf(actor.stagger_duration, .01), 0.0, 1.0) * PI) if actor.ai_state == DungeonEnemy.AIState.STAGGER else 0.0
	# Low breathing / weight transfer stays on the ground, including attacks.
	var roll := sin(phase * TAU) * .035 * movement_blend
	var body := Transform3D(Basis(Vector3.FORWARD, roll), Vector3(0, .055 + .025 * lunge, -.13 * lunge + .025 * recoil))
	for bone in poses.size(): poses[bone] = body * poses[bone]
	_lower_body(poses, body.basis)
	# Keep the alert face forward instead of the sleeping head's sideways tilt.
	var head := rig.find_bone("Head")
	_branch(poses, head, Transform3D(upright[head].basis, poses[head].origin))
	for side: String in ["L", "R"]:
		var p := fposmod(phase + (0.0 if side == "L" else .5), 1.0)
		var contact := p < STANCE
		var hand_z := -.68 + STRIDE * p if contact else lerpf(-.68 + STRIDE * STANCE, -.68, smoothstep(STANCE, 1.0, p))
		var lift := 0.0 if contact else sin((p - STANCE) / (1.0 - STANCE) * PI) * .15 * movement_blend
		var target := Vector3(-.48 if side == "L" else .48, -.9 + .12 + lift, hand_z)
		_arm(poses, side, target)
		hand_targets[side] = actor.global_transform * target
		planted[side] = contact or movement_blend < .01
	# Use only the source jaw/tongue articulation for the bite, never its standing torso.
	if biting:
		for bone in order:
			var name := rig.get_bone_name(bone)
			if name.begins_with("Jaw") or name.begins_with("Tongue"):
				var parent := rig.get_bone_parent(bone)
				if parent >= 0: poses[bone] = poses[parent] * rig.get_bone_pose(bone)
	actor.visual_root.position = actor.visual_base_position
	actor.visual_root.rotation = Vector3.ZERO
	var to_rig: Transform3D = rig.global_transform.affine_inverse() * actor.global_transform
	var weight := smoothstep(0.0, 1.0, blend)
	for bone in order:
		rig.set_bone_global_pose(bone, to_rig * entry[bone].interpolate_with(poses[bone], weight))
	actor.animation_clip = "crawl_bite" if biting else ("crawl_hit" if actor.ai_state == DungeonEnemy.AIState.STAGGER else ("crawl" if actor.ai_state == DungeonEnemy.AIState.CHASE else "crawl_idle"))
	if recovering: actor.animation_clip = "crawl_recover"
	actor.animation_sample = phase

func snapshot() -> Dictionary:
	return {"active": active, "blend": blend, "phase": phase, "hands": hand_targets.duplicate(), "planted": planted.duplicate(), "feet": foot_targets.duplicate(), "movement_blend": movement_blend}
