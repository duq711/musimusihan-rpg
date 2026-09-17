extends SceneTree
const CREEP := preload("res://scripts/creep_enemy.gd")
var failures: Array[String] = []
var report: Array = []

func _init() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
		push_error("RAGDOLL: " + message)

func run() -> void:
	if not CREEP.is_available():
		print("CREEP RAGDOLL TEST PASS: licensed model missing; physical rig checks SKIPPED")
		quit(); return
	var saved_cursor := Input.mouse_mode
	var source_hash := FileAccess.get_sha256(CREEP.MODEL_PATH)
	for direction: Vector3 in [Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(0, 0, -1)]:
		await scenario(direction)
	await scenario(Vector3(0, 0, 1), true)
	check(source_hash == FileAccess.get_sha256(CREEP.MODEL_PATH), "original model preserved")
	check(saved_cursor == Input.mouse_mode, "cursor preserved")
	var dir := "res://artifacts/visual_qa/creep_ragdoll"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var file := FileAccess.open(dir + "/physics_report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	print("CREEP RAGDOLL TEST ", "PASS" if failures.is_empty() else "FAIL", ": ", failures)
	quit(0 if failures.is_empty() else 1)

func solid(parent: Node3D, size: Vector3, pos: Vector3) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 2
	body.collision_mask = 0
	parent.add_child(body)
	body.position = pos
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)

func scenario(direction: Vector3, front_wall := false) -> void:
	var world := Node3D.new()
	root.add_child(world)
	solid(world, Vector3(20, .2, 20), Vector3(0, -.1, 0))
	if direction.x > .5:
		solid(world, Vector3(.2, 3, 8), Vector3(1.5, 1.5, 0))
	if front_wall:
		solid(world, Vector3(8, 3, .2), Vector3(0, 1.5, 1.35))
	var actor = CREEP.new()
	actor.position = Vector3(0, .9, 0)
	world.add_child(actor)
	actor.process_mode = Node.PROCESS_MODE_PAUSABLE
	for frame in 12: await physics_frame
	check(actor.ragdoll.phase == "living" and actor.ragdoll.parts.is_empty(), "no physical bodies while alive")
	var signals := [0]
	actor.defeated.connect(func(_actor): signals[0] += 1)
	var prior: Transform3D = actor.skeleton.get_bone_pose(actor.skeleton.find_bone("Head"))
	actor.receive_hit(10000, actor.global_position - direction * 2, 1.0, false)
	check(actor.ragdoll.phase == "reaction" and actor.ai_state == DungeonEnemy.AIState.DEAD, "fatal hit begins short reaction")
	check(actor.skeleton.get_bone_pose(actor.skeleton.find_bone("Head")).is_equal_approx(prior), "no pose snap on fatal frame")
	check(signals[0] == 1 and actor.collision_layer == 0, "single immediate death event and root collision disabled")
	var samples: Array = []
	var simulation_seen := false
	var lowest := INF
	var highest := -INF
	var max_separation := 0.0
	for frame in 600:
		await physics_frame
		if actor.ragdoll.phase == "simulating": simulation_seen = true
		for entry: Dictionary in actor.ragdoll.pose_order:
			var body: RigidBody3D = entry.body
			check(body.global_position.is_finite(), "finite physical position")
			lowest = minf(lowest, body.global_position.y)
			highest = maxf(highest, body.global_position.y)
			if not str(entry.parent).is_empty():
				var parent: Dictionary = actor.ragdoll.parts[entry.parent]
				var bone_world: Transform3D = body.global_transform * entry.body_to_bone
				var parent_anchor: Vector3 = parent.body.global_transform * entry.parent_anchor
				max_separation = maxf(max_separation, bone_world.origin.distance_to(parent_anchor))
		if frame % 30 == 0: samples.append(actor.ragdoll.snapshot())
		if actor.ragdoll.phase == "settled": break
	print("RAGDOLL SCENARIO ", direction, " phase=", actor.ragdoll.phase, " time=", actor.ragdoll.simulation_time, " lowest=", lowest, " highest=", highest, " separation=", max_separation)
	check(simulation_seen and actor.ragdoll.parts.size() == 20 and actor.ragdoll.joints.size() == 19, "connected 20-body simulation ran")
	check(lowest > -.12 and highest < 3.3, "floor collision and bounded energy")
	check(max_separation < .13, "joints keep limbs attached")
	check(actor.ragdoll.phase == "settled", "corpse settles within ten seconds")
	var torso: RigidBody3D = actor.ragdoll.parts.Torso.body
	check(torso.global_position.y < .65, "torso actually collapses to the ground")
	if direction.x > .5:
		for entry: Dictionary in actor.ragdoll.pose_order:
			check(entry.body.global_position.x < 1.45, "wall prevents body centres passing through")
	var settled: Dictionary = actor.ragdoll.snapshot()
	for frame in 30: await physics_frame
	check(settled.positions == actor.ragdoll.snapshot().positions, "settled pose remains fixed")
	actor.receive_hit(10000, Vector3.ZERO, 1.0, false)
	check(signals[0] == 1 and actor.ragdoll.phase == "settled", "corpse hits do not restart death/reward")
	report.append({"direction": direction, "front_wall": front_wall, "samples": samples, "final": actor.ragdoll.snapshot(), "lowest": lowest, "highest": highest, "max_joint_separation": max_separation})
	world.queue_free()
	await process_frame
