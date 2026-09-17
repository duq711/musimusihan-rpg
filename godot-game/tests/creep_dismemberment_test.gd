extends SceneTree
const CREEP := preload("res://scripts/creep_enemy.gd")
const PARTS := preload("res://scripts/creep_dismemberment.gd")
const PREVIEW := preload("res://tests/creep_dismemberment_preview.gd")
var failures: Array[String] = []
var report: Array = []

func _init() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
		push_error("DISMEMBERMENT: " + message)

func run() -> void:
	check(PREVIEW.CUT_CASES.size() == 3, "real renderer harness loads with arm, leg, head cases")
	if not CREEP.is_available() or not ResourceLoader.exists(PARTS.MODEL_PATH):
		print("CREEP DISMEMBERMENT TEST SKIP: install local original and segmented model")
		quit(); return
	var original := FileAccess.get_sha256(CREEP.MODEL_PATH)
	var cursor := Input.mouse_mode
	for region: String in PARTS.REGIONS:
		await scenario(region)
	await distributed()
	await multiple_parts()
	await stance_grounding()
	await attachments_follow_cut()
	await missing_arm_contacts()
	check(original == FileAccess.get_sha256(CREEP.MODEL_PATH), "original model unchanged")
	check(cursor == Input.mouse_mode, "cursor unchanged")
	var path := "res://artifacts/visual_qa/creep_dismemberment"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path))
	var file := FileAccess.open(path + "/physics_report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	print("CREEP DISMEMBERMENT TEST ", "PASS" if failures.is_empty() else "FAIL", ": ", failures)
	quit(0 if failures.is_empty() else 1)

func fixture() -> Dictionary:
	var world := Node3D.new()
	root.add_child(world)
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 2
	world.add_child(floor_body)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(12, .2, 12)
	collision.shape = shape
	floor_body.add_child(collision)
	collision.position.y = -.1
	var actor = CREEP.new()
	actor.position = Vector3(0, .9, 0)
	actor.health = 82
	actor.max_health = 82
	world.add_child(actor)
	actor.set_physics_process(false)
	return {"world": world, "actor": actor}

func strike(actor, region: String, amount := 18.0) -> void:
	var point: Vector3 = actor.dismemberment.hit_point_for_region(region)
	actor.receive_located_hit(amount, Vector3(0, .9, -3), .5, region == "head", point)

func execution_gate(actor) -> void:
	# The local execution feature is optional on public branches. At low health
	# a knocked-down stagger must still be protected while physics owns the rig.
	if not actor.has_method("is_execution_vulnerable") or not actor.is_knocked_down(): return
	var saved_health: float = actor.health
	actor.health = actor.max_health * .1
	check(not bool(actor.call("is_execution_vulnerable")), "temporary fall/recovery cannot be reserved for execution")
	actor.health = saved_health

func scenario(region: String) -> void:
	var f := fixture()
	var actor = f.actor
	for frame in 3: await physics_frame
	check(actor.dismemberment.enabled, "segmented skin and all caps installed")
	var counts := [0]
	actor.defeated.connect(func(_actor): counts[0] += 1)
	var aim: Vector3 = actor.dismemberment.hit_point_for_region(region)
	check(actor.dismemberment.region_at_point(aim) == region, "anatomical aim point: " + region)
	var query: Dictionary = actor.query_located_hit(aim + Vector3(0, 0, -.2), aim, .0)
	check(not query.is_empty() and query.region == region, "current posed ray contact: " + region)
	for radius: float in [0.0, .10, .18]:
		for angle in 8:
			var direction := Vector3(cos(angle * TAU / 8), .3, sin(angle * TAU / 8)).normalized()
			var contact: Dictionary = actor.query_located_hit(aim + direction * 3, aim, radius)
			if not contact.is_empty():
				check(actor.dismemberment.region_at_point(contact.position) == contact.region, "swept contact resolves to the same anatomical region")
	strike(actor, region)
	check(actor.dismemberment.severed.is_empty(), "one hit cannot sever: " + region)
	strike(actor, region)
	var snapshot: Dictionary = actor.dismemberment.snapshot()
	check(snapshot.severed == [region] and snapshot.detached_bodies == 1, "exactly struck part detached: " + region)
	check(snapshot.damage[region] == 36.0, "localized accumulated damage: " + region)
	for other: String in PARTS.REGIONS:
		if other != region: check(snapshot.damage[other] == 0, "other regions retain damage zero")
	if snapshot.detached_bodies != 1:
		f.world.queue_free(); await process_frame; return
	var detached: RigidBody3D = actor.dismemberment.detached[0]
	var start := detached.global_position
	var vertex_count := 0
	for child in detached.get_children():
		if child is MeshInstance3D:
			for surface in child.mesh.get_surface_count():
				var arrays: Array = child.mesh.surface_get_arrays(surface)
				vertex_count += arrays[Mesh.ARRAY_VERTEX].size()
				check(arrays[Mesh.ARRAY_BONES] == null and arrays[Mesh.ARRAY_WEIGHTS] == null, "detached surface cannot be pulled by living bones")
				for vertex: Vector3 in arrays[Mesh.ARRAY_VERTEX]:
					check(vertex.is_finite() and vertex.length() < 2.5, "finite posed geometry bounded in world metres")
	check(vertex_count > 100, "actual source geometry detached, not a placeholder")
	for mesh: MeshInstance3D in actor.dismemberment.meshes[region]: check(not mesh.visible, "removed limb invisible on living skin")
	for cap: MeshInstance3D in actor.dismemberment.body_caps[region]: check(cap.visible, "body cut is capped")
	check((actor.ai_state == DungeonEnemy.AIState.DEAD) == (region == "head"), "only head severance immediately kills")
	check(counts[0] == int(region == "head"), "no limb-cut loot, exactly one decapitation reward")
	if region != "head":
		if region.ends_with("leg"):
			check(actor.is_knocked_down(), "surviving leg cut first enters physical fall")
			check(actor.move_speed < actor.dismemberment.base_move_speed, "missing leg reduces travel")
		else:
			actor._set_state(DungeonEnemy.AIState.WINDUP)
			check(actor.ai_state == DungeonEnemy.AIState.WINDUP, "surviving arm-cut Creep can attack")
	for frame in 300: await physics_frame
	check(detached.global_position.distance_to(start) > .15, "released part actually falls")
	check(detached.global_position.y > -.35 and detached.global_position.length() < 8, "floor collision prevents runaway part")
	var paused_position := detached.global_transform
	paused = true
	for frame in 3: await process_frame
	check(detached.global_transform.is_equal_approx(paused_position), "pause holds detached physics")
	paused = false
	if region != "head":
		actor.receive_hit(1000, Vector3(0, .9, -3), 1.0, false)
		for frame in 40: await physics_frame
		for bone: String in PARTS.REGION_BONES[region]: check(not actor.ragdoll.parts.has(bone), "later ragdoll never recreates detached part")
		check(counts[0] == 1, "eventual body death rewards once")
	for frame in 600:
		if actor.ragdoll.phase == "settled": break
		await physics_frame
	check(actor.ragdoll.phase == "settled", "ragdoll with a missing part settles: " + region)
	check(actor.dismemberment.detached.size() == 1, "later death keeps the same detached object")
	report.append({"region": region, "snapshot": snapshot, "vertices": vertex_count, "final_part_position": detached.global_position, "death_events": counts[0]})
	f.world.queue_free()
	await process_frame

func distributed() -> void:
	var f := fixture()
	var actor = f.actor
	actor.health = 200
	actor.max_health = 200
	for region: String in PARTS.REGIONS: strike(actor, region, 18)
	check(actor.dismemberment.severed.is_empty(), "distributed hits never share a severance meter")
	strike(actor, "left_arm", 0)
	check(actor.dismemberment.hit_counts.left_arm == 1, "zero damage is not a second hit")
	strike(actor, "left_arm", 18)
	check(actor.dismemberment.severed == ["left_arm"], "returning to same region continues only its accumulated damage")
	f.world.queue_free(); await process_frame

func multiple_parts() -> void:
	var f := fixture()
	var actor = f.actor
	actor.health = 400
	actor.max_health = 400
	for region in ["left_arm", "right_arm", "left_leg", "right_leg"]:
		strike(actor, region); strike(actor, region)
	check(actor.ai_state != DungeonEnemy.AIState.DEAD and actor.dismemberment.detached.size() == 4, "four missing limbs do not force death")
	check(actor.is_knocked_down(), "four-limb loss must physically fall before biting")
	actor.set_physics_process(true)
	for frame in 1200:
		await physics_frame
		execution_gate(actor)
		if not actor.is_knocked_down(): break
	check(not actor.is_knocked_down(), "armless body settles and completes crawl recovery")
	actor.set_physics_process(false)
	actor.attack_index = 0
	actor._set_state(DungeonEnemy.AIState.WINDUP)
	check(actor.attack_index == 0 and actor.animation_clip == "crawl_bite", "armless crawling Creep only selects low bite")
	check(is_equal_approx(actor.move_speed, actor.dismemberment.base_move_speed * .18), "two missing legs use crawl speed")
	strike(actor, "head"); strike(actor, "head")
	check(actor.ai_state == DungeonEnemy.AIState.DEAD and actor.dismemberment.detached.size() == 5, "head cut terminates remaining combat")
	f.world.queue_free(); await process_frame

func stance_grounding() -> void:
	for legs in [1, 2]:
		var f := fixture()
		var actor = f.actor
		actor.health = 400; actor.max_health = 400
		strike(actor, "left_leg"); strike(actor, "left_leg")
		if legs == 2:
			strike(actor, "right_leg"); strike(actor, "right_leg")
		actor.set_physics_process(true)
		for frame in 1200:
			await physics_frame
			execution_gate(actor)
			if not actor.is_knocked_down(): break
		check(not actor.is_knocked_down(), "grounding samples begin after physical recovery")
		actor.set_physics_process(false)
		actor._set_state(DungeonEnemy.AIState.CHASE)
		for sample in 8:
			actor.state_time = sample * .22
			actor._update_visual_pose(.25)
			var lowest := INF
			for mesh: MeshInstance3D in actor.visual_meshes:
				if not mesh.visible: continue
				var baked: ArrayMesh = actor.dismemberment._bake_world_mesh(mesh, Vector3.ZERO)
				for surface in baked.get_surface_count():
					for vertex: Vector3 in baked.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]: lowest = minf(lowest, vertex.y)
			check(lowest > -.12, "remaining skin stays above floor after leg loss: " + str(lowest))
		f.world.queue_free(); await process_frame

func attachments_follow_cut() -> void:
	var f := fixture()
	var actor = f.actor
	var point: Vector3 = actor.dismemberment.hit_point_for_region("right_arm")
	var anchor: Node3D = actor.get_located_hit_attachment(point)
	strike(actor, "right_arm")
	point = actor.dismemberment.hit_point_for_region("right_arm")
	actor.receive_located_hit(18, Vector3(0, .9, -3), .5, false, point)
	var body: RigidBody3D = actor.dismemberment.detached[0]
	check(anchor.get_parent() == body and not anchor.is_set_as_top_level(), "earlier arrow anchor moves to detached body")
	check(actor.get_located_hit_attachment(point) == body, "cutting arrow attaches to the just-severed part")
	var health: float = actor.health
	actor.receive_located_hit(18, Vector3.ZERO, .5, false, Vector3(0, 100, 0))
	check(actor.health == health, "invalid anatomical contact does not damage torso")
	f.world.queue_free(); await process_frame

func missing_arm_contacts() -> void:
	for region: String in ["right_arm", "left_arm"]:
		var f := fixture()
		var actor = f.actor
		var victim := PREVIEW.TargetDummy.new()
		f.world.add_child(victim)
		victim.position = Vector3(0, .9, -1.2)
		actor.target = victim
		strike(actor, region); strike(actor, region)
		actor.attack_index = 0
		actor._set_state(DungeonEnemy.AIState.WINDUP)
		actor._set_state(DungeonEnemy.AIState.ACTIVE)
		actor.state_time = .06
		actor._resolve_active_attack()
		check(victim.contacts == int(region == "left_arm"), "right contact only deals damage if right arm survives")
		actor.state_time = .34
		actor._resolve_active_attack()
		check(victim.contacts == 1, "one-arm punch cycle contains exactly one real hit")
		f.world.queue_free(); await process_frame
