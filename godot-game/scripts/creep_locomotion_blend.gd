extends RefCounted
## Manual AnimationPlayer seeking does not advance its built-in crossfade.
## Blend the rendered skeleton explicitly while keeping combat's sample clock.
const EXIT_SECONDS := 0.28
const ENTER_SECONDS := 0.12
const SOURCE_WALK_SPEED := 2.2
const PHASE_SAMPLES := 64
const MATCH_BONES := {"Foot.L": 2.0, "Foot.R": 2.0, "Torso": 0.35, "Chest": 0.20}

var entry: Array[Transform3D] = []
var elapsed := 0.0
var duration := EXIT_SECONDS
var walk_sample := 0.0
var walk_speed := 0.0
var clock_active := false
var _walk_candidates: Array[Dictionary] = []

func cancel() -> void:
	entry.clear()
	elapsed = 0.0
	clock_active = false
	walk_speed = 0.0

func begin_walk(rig: Skeleton3D, player: AnimationPlayer) -> void:
	_capture(rig, EXIT_SECONDS)
	var reference := _landmarks(rig)
	# Cache local-space foot/chest positions, never world positions or poses from
	# another actor. The source walk has multiple strides, so scan the full clip.
	if _walk_candidates.is_empty():
		var length := player.get_animation("walk").length
		player.play("walk")
		for step in PHASE_SAMPLES:
			var sample := length * float(step) / PHASE_SAMPLES
			player.seek(sample, true)
			_walk_candidates.append({"sample": sample, "points": _landmarks(rig)})
	var best_cost := INF
	for candidate in _walk_candidates:
		var cost := 0.0
		for bone: String in reference:
			cost += reference[bone].distance_squared_to(candidate.points[bone]) * MATCH_BONES[bone]
		if cost < best_cost:
			best_cost = cost
			walk_sample = candidate.sample
	clock_active = true
	walk_speed = 0.0
	# Seeking candidates must never display an intermediate pose.
	for bone in entry.size():
		rig.set_bone_pose(bone, entry[bone])

func begin_attack(rig: Skeleton3D) -> void:
	_capture(rig, ENTER_SECONDS)
	clock_active = false
	walk_speed = 0.0

func _capture(rig: Skeleton3D, seconds: float) -> void:
	entry.clear()
	for bone in rig.get_bone_count():
		entry.append(rig.get_bone_pose(bone))
	elapsed = 0.0
	duration = seconds

func _landmarks(rig: Skeleton3D) -> Dictionary:
	var points := {}
	for name: String in MATCH_BONES:
		var index := rig.find_bone(name)
		if index >= 0:
			points[name] = rig.get_bone_global_pose(index).origin
	return points

func sample_walk(delta: float, speed: float, direct_sample: float, length: float) -> float:
	if delta > 0.0:
		if not clock_active:
			walk_sample = 0.0
			clock_active = true
		walk_speed = maxf(speed, 0.0)
		walk_sample = fposmod(walk_sample + delta * walk_speed / SOURCE_WALK_SPEED, length)
	# Offline source-clip inspection deliberately seeks with delta=0. Runtime
	# entries retain their own clock even on the state change's zero-delta sample.
	return walk_sample if clock_active else direct_sample

func apply(rig: Skeleton3D, delta: float) -> void:
	if entry.is_empty():
		return
	elapsed = minf(elapsed + maxf(delta, 0.0), duration)
	var weight := smoothstep(0.0, duration, elapsed)
	for bone in entry.size():
		# Preserve the exact entry matrix on the state-change sample; avoid
		# decomposing/recomposing it before any transition time has elapsed.
		rig.set_bone_pose(bone, entry[bone] if weight == 0.0 else entry[bone].interpolate_with(rig.get_bone_pose(bone), weight))
	if elapsed >= duration:
		entry.clear()

func snapshot() -> Dictionary:
	return {"active": not entry.is_empty(), "elapsed": elapsed, "duration": duration,
		"walk_sample": walk_sample, "walk_speed": walk_speed}
