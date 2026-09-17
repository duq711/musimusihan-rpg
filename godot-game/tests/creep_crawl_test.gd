extends SceneTree
## Production rig/AI checks: broad physical bounds, not exact artistic angles.
const CREEP := preload("res://scripts/creep_enemy.gd")
const PARTS := preload("res://scripts/creep_dismemberment.gd")
const PREVIEW := preload("res://tests/creep_dismemberment_preview.gd")
const CRAWL_PREVIEW := preload("res://tests/creep_crawl_preview.gd")
var failures: Array[String] = []
var report: Array = []

func _init() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("CREEP CRAWL: " + message)

func run() -> void:
	check(CRAWL_PREVIEW.CRAWL_CASES.size() == 3, "GPU review covers left, right and both legs")
	if not CREEP.is_available() or not ResourceLoader.exists(PARTS.MODEL_PATH):
		print("CREEP CRAWL TEST PASS: licensed models missing; rig/AI checks SKIPPED")
		quit(); return
	var source_hash := FileAccess.get_sha256(CREEP.MODEL_PATH)
	var cursor := Input.mouse_mode
	for legs: Array in [["left_leg"], ["right_leg"], ["left_leg", "right_leg"]]:
		await scenario(legs)
	await optional_execution()
	check(source_hash == FileAccess.get_sha256(CREEP.MODEL_PATH), "source model preserved")
	check(cursor == Input.mouse_mode, "cursor preserved")
	var path := "res://artifacts/visual_qa/creep_crawl"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path))
	var file := FileAccess.open(path + "/physics_report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	print("CREEP CRAWL TEST ", "PASS" if failures.is_empty() else "FAIL", ": ", failures)
	quit(0 if failures.is_empty() else 1)

func fixture() -> Dictionary:
	var world := Node3D.new()
	root.add_child(world)
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 2
	floor_body.collision_mask = 0
	world.add_child(floor_body)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(24, .2, 24)
	collision.shape = shape
	floor_body.add_child(collision)
	collision.position.y = -.1
	var actor = CREEP.new()
	actor.position = Vector3(0, .9, 0)
	actor.health = 500
	actor.max_health = 500
	world.add_child(actor)
	actor.set_physics_process(false)
	var victim := PREVIEW.TargetDummy.new()
	world.add_child(victim)
	victim.position = Vector3(0, .9, -8)
	actor.target = victim
	return {"world": world, "actor": actor, "victim": victim}

func bone_world(actor, bone_name: String) -> Vector3:
	var index: int = actor.skeleton.find_bone(bone_name)
	assert(index >= 0, "source bone must exist: " + bone_name)
	return (actor.skeleton.global_transform * actor.skeleton.get_bone_global_pose(index)).origin

func strike(actor, region: String) -> void:
	var point: Vector3 = actor.dismemberment.hit_point_for_region(region)
	actor.receive_located_hit(18.0, Vector3(0, .9, -3), .5, false, point)

func advance(actor, frames: int) -> void:
	for frame in frames:
		await physics_frame
		# The game resolves enemy contacts after advancing actor physics.
		actor._resolve_active_attack()

func low_pose(actor, label: String) -> Dictionary:
	var chest := bone_world(actor, "Chest")
	var head := bone_world(actor, "Head")
	check(chest.is_finite() and head.is_finite(), label + ": finite torso/head")
	check(chest.y < .95, label + ": chest stays low: " + str(chest.y))
	check(head.y < 1.25, label + ": head never resumes standing pose: " + str(head.y))
	check(chest.y > -.10 and head.y > -.10, label + ": torso/head remain above floor")
	check(actor.get_aim_point().distance_to(chest) < .01, label + ": aim follows the low chest")
	check(str(actor.animation_clip).begins_with("crawl"), label + ": crawling owns every living pose")
	return {"chest": chest, "head": head, "clip": actor.animation_clip}

func skin_floor(actor, label: String) -> float:
	var lowest := INF
	for mesh: MeshInstance3D in actor.visual_meshes:
		if not mesh.visible: continue
		var baked: ArrayMesh = actor.dismemberment._bake_world_mesh(mesh, Vector3.ZERO)
		for surface in baked.get_surface_count():
			for vertex: Vector3 in baked.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]:
				lowest = minf(lowest, vertex.y)
	check(lowest > -.15, label + ": remaining skin stays above floor: " + str(lowest))
	return lowest

func posed_queries(actor, label: String) -> void:
	var contacts := 0
	for region: String in ["head", "torso", "left_arm", "right_arm", "left_leg", "right_leg"]:
		if region in actor.dismemberment.severed: continue
		var point: Vector3 = actor.dismemberment.hit_point_for_region(region)
		for direction: Vector3 in [Vector3.UP, Vector3.LEFT, Vector3.RIGHT, Vector3.FORWARD]:
			var contact: Dictionary = actor.query_located_hit(point + direction * 2.5, point, .08)
			if contact.is_empty(): continue
			contacts += 1
			check(contact.region not in actor.dismemberment.severed, label + ": missing parts cannot be hit")
			check(actor.dismemberment.region_at_point(contact.position) == contact.region, label + ": posed query and anatomical damage agree")
	check(contacts >= 8, label + ": low body has real queryable anatomy")

func scenario(legs: Array) -> void:
	var f := fixture()
	var actor = f.actor
	var label := "+".join(legs)
	for frame in 3: await physics_frame
	check(not actor.is_crawling(), label + ": intact creature remains upright")
	var original_head := bone_world(actor, "Head")
	for region: String in legs:
		strike(actor, region)
		if actor.dismemberment.severed.is_empty():
			check(not actor.is_crawling(), label + ": one ordinary hit does not start crawling")
		strike(actor, region)
	check(actor.is_crawling() and actor.dismemberment.severed.size() == legs.size(), label + ": real cuts activate crawling for either/both legs")
	check(actor.ai_state != DungeonEnemy.AIState.DEAD, label + ": survives limb cuts")
	var cut_head := bone_world(actor, "Head")
	check(original_head.distance_to(cut_head) < .45, label + ": cutting frame does not teleport into prone pose")
	actor.velocity = Vector3.ZERO
	actor._set_state(DungeonEnemy.AIState.CHASE)
	actor.set_physics_process(true)
	var blend_samples: Array = []
	for frame in 90:
		await physics_frame
		actor._resolve_active_attack()
		if frame % 15 == 0:
			blend_samples.append(actor.crawl.blend)
			check(actor.crawl.blend >= 0.0 and actor.crawl.blend <= 1.0, label + ": normalized transition")
	check(actor.crawl.active and actor.crawl.blend > .99, label + ": prone transition completes")
	for i in range(1, blend_samples.size()):
		check(float(blend_samples[i]) >= float(blend_samples[i - 1]), label + ": no backward jump during transition")
	var low_samples := [low_pose(actor, label + "/chase")]
	var minimum_skin := skin_floor(actor, label + "/chase")
	posed_queries(actor, label + "/chase")
	var start: Vector3 = actor.global_position
	var minimum_hand := Vector2(INF, INF)
	var maximum_hand := Vector2(-INF, -INF)
	var relative_min := INF
	var relative_max := -INF
	for frame in 120:
		await physics_frame
		actor._resolve_active_attack()
		var left: Vector3 = actor.to_local(bone_world(actor, "Hand.L"))
		var right: Vector3 = actor.to_local(bone_world(actor, "Hand.R"))
		minimum_hand = minimum_hand.min(Vector2(left.z, right.z))
		maximum_hand = maximum_hand.max(Vector2(left.z, right.z))
		relative_min = minf(relative_min, left.z - right.z)
		relative_max = maxf(relative_max, left.z - right.z)
		if frame % 30 == 0:
			low_samples.append(low_pose(actor, label + "/moving"))
			if frame == 60: minimum_skin = minf(minimum_skin, skin_floor(actor, label + "/pull"))
	check(actor.global_position.distance_to(start) > .20, label + ": actual AI moves the low body toward its target")
	check((maximum_hand - minimum_hand).x > .04 and (maximum_hand - minimum_hand).y > .04, label + ": both real hand bones move through reaching/pulling")
	check(relative_max - relative_min > .06, label + ": arms alternate instead of rigidly sliding together")
	var paused_position: Transform3D = actor.global_transform
	var paused_hand := bone_world(actor, "Hand.L")
	var paused_phase: float = actor.crawl.phase
	paused = true
	for frame in 4: await process_frame
	check(actor.global_transform.is_equal_approx(paused_position) and bone_world(actor, "Hand.L").is_equal_approx(paused_hand), label + ": pause freezes travel and actual skin pose")
	check(is_equal_approx(actor.crawl.phase, paused_phase), label + ": pause freezes crawl clock")
	paused = false
	# Let production AI cycle windup -> bite contact -> recovery twice.
	f.victim.global_position = actor.global_position + Vector3(0, 0, -.9)
	actor.velocity = Vector3.ZERO
	actor.attack_index = 0
	actor._set_state(DungeonEnemy.AIState.WINDUP)
	var seen_states: Dictionary = {}
	for frame in 220:
		await physics_frame
		actor._resolve_active_attack()
		seen_states[actor.ai_state] = true
		if frame % 20 == 0:
			low_samples.append(low_pose(actor, label + "/bite"))
			check(actor.attack_index == 0, label + ": crawling never selects standing punches")
	check(seen_states.has(DungeonEnemy.AIState.WINDUP) and seen_states.has(DungeonEnemy.AIState.ACTIVE) and seen_states.has(DungeonEnemy.AIState.RECOVERY), label + ": real attack states all execute")
	check(f.victim.contacts >= 2, label + ": surviving prone creature makes real bite contacts")
	check(actor.attack_range < 1.5, label + ": crawling uses shorter reach")
	posed_queries(actor, label + "/bite")
	minimum_skin = minf(minimum_skin, skin_floor(actor, label + "/bite"))
	actor.receive_hit(1, actor.global_position + Vector3(0, 0, -3), 0.0, false)
	await advance(actor, 8)
	low_samples.append(low_pose(actor, label + "/stagger"))
	check(actor.animation_clip == "crawl_hit", label + ": recoil also stays prone")
	minimum_skin = minf(minimum_skin, skin_floor(actor, label + "/stagger"))
	actor.target = null
	actor._set_state(DungeonEnemy.AIState.IDLE)
	await advance(actor, 20)
	low_samples.append(low_pose(actor, label + "/idle"))
	check(actor.animation_clip == "crawl_idle", label + ": resting never stands up again")
	for side: String in ["L", "R"]:
		var hand_height := bone_world(actor, "Hand." + side).y
		check(bool(actor.crawl.planted.get(side, false)), label + ": resting hand is planted: " + side)
		check(hand_height > -.05 and hand_height < .22, label + ": resting palm returns to ground: " + side + " " + str(hand_height))
	var head_before_death := bone_world(actor, "Head")
	actor.velocity = Vector3.ZERO
	actor.receive_hit(1000, actor.global_position + Vector3(0, 0, -2), .5, false)
	check(bone_world(actor, "Head").distance_to(head_before_death) < .03, label + ": fatal frame preserves prone pose")
	var maximum_death_head := head_before_death.y
	for frame in 20:
		await physics_frame
		maximum_death_head = maxf(maximum_death_head, bone_world(actor, "Head").y)
	check(maximum_death_head < 1.25, label + ": death reaction cannot return to upright hit animation")
	for frame in 600:
		if actor.ragdoll.phase == "settled": break
		await physics_frame
	check(actor.ragdoll.phase == "settled", label + ": prone corpse ragdoll settles")
	for region: String in legs:
		for bone: String in PARTS.REGION_BONES[region]:
			check(not actor.ragdoll.parts.has(bone), label + ": death does not recreate removed leg")
	report.append({"legs": legs, "transition": blend_samples, "low_poses": low_samples, "hand_ranges": maximum_hand - minimum_hand, "arm_alternation": relative_max - relative_min, "minimum_skin_y": minimum_skin, "contacts": f.victim.contacts, "maximum_death_head_y": maximum_death_head, "crawl": actor.crawl.snapshot(), "ragdoll": actor.ragdoll.snapshot()})
	f.world.queue_free()
	await process_frame

func optional_execution() -> void:
	# Some public branches do not include the separate execution feature yet.
	# Dynamic calls verify the local integration without making it a dependency.
	var f := fixture()
	var actor = f.actor
	if not actor.has_method("begin_execution") or not actor.has_method("advance_execution_pose") or not actor.has_method("finish_execution"):
		print("CREEP CRAWL: optional execution feature absent; integration check SKIPPED")
		f.world.queue_free()
		await process_frame
		return
	strike(actor, "left_leg")
	strike(actor, "left_leg")
	actor.target = null
	actor.velocity = Vector3.ZERO
	actor.set_physics_process(true)
	await advance(actor, 45)
	actor.health = actor.max_health * .1
	actor._set_state(DungeonEnemy.AIState.STAGGER, 1.0)
	check(bool(actor.call("begin_execution", f.victim)), "crawl/execution: real low-health target can enter execution")
	var samples: Array = [low_pose(actor, "crawl/execution/entry")]
	for elapsed: float in [.2, .7]:
		actor.call("advance_execution_pose", elapsed)
		samples.append(low_pose(actor, "crawl/execution/" + str(elapsed)))
		await physics_frame
	var prior := bone_world(actor, "Head")
	check(bool(actor.call("finish_execution", f.victim)), "crawl/execution: finisher completes normally")
	check(actor.ai_state == DungeonEnemy.AIState.DEAD, "crawl/execution: finish reaches actual death")
	check(bone_world(actor, "Head").distance_to(prior) < .03, "crawl/execution: death retains prone entry pose")
	var maximum_head := prior.y
	for frame in 20:
		await physics_frame
		maximum_head = maxf(maximum_head, bone_world(actor, "Head").y)
	check(maximum_head < 1.25, "crawl/execution: reaction never snaps upright")
	report.append({"case": "optional_execution", "poses": samples, "maximum_head_y": maximum_head})
	f.world.queue_free()
	await process_frame
