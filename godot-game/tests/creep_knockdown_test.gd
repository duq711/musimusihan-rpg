extends SceneTree
## Real articulated physics -> supported rest -> continuous living crawl.
const CREEP := preload("res://scripts/creep_enemy.gd")
const PARTS := preload("res://scripts/creep_dismemberment.gd")
const PREVIEW := preload("res://tests/creep_dismemberment_preview.gd")
var failures: Array[String] = []
var report: Array = []

func _init() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("CREEP KNOCKDOWN: " + message)

func run() -> void:
	if not CREEP.is_available() or not ResourceLoader.exists(PARTS.MODEL_PATH):
		print("CREEP KNOCKDOWN TEST PASS: licensed models absent; physical checks SKIPPED")
		quit(); return
	var source_hash := FileAccess.get_sha256(CREEP.MODEL_PATH)
	var cursor := Input.mouse_mode
	for legs: Array in [["left_leg"], ["right_leg"], ["left_leg", "right_leg"]]:
		await ground_scenario(legs)
	await airborne_scenario()
	await fatal_during_fall()
	check(source_hash == FileAccess.get_sha256(CREEP.MODEL_PATH), "original asset preserved")
	check(cursor == Input.mouse_mode, "no hardware input or cursor changes")
	var path := "res://artifacts/visual_qa/creep_knockdown"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path))
	var file := FileAccess.open(path + "/physics_report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	print("CREEP KNOCKDOWN TEST ", "PASS" if failures.is_empty() else "FAIL", ": ", failures)
	quit(0 if failures.is_empty() else 1)

func fixture(floor_enabled := true, height := .9) -> Dictionary:
	var world := Node3D.new()
	root.add_child(world)
	if floor_enabled:
		var floor_body := StaticBody3D.new()
		floor_body.collision_layer = 2
		floor_body.collision_mask = 0
		world.add_child(floor_body)
		var collision := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(30, .2, 30)
		collision.shape = shape
		floor_body.add_child(collision)
		collision.position.y = -.1
	var actor = CREEP.new()
	actor.position = Vector3(0, height, 0)
	actor.health = 500
	actor.max_health = 500
	world.add_child(actor)
	actor.set_physics_process(false)
	var victim := PREVIEW.TargetDummy.new()
	world.add_child(victim)
	victim.position = Vector3(0, height, -8)
	actor.target = victim
	return {"world": world, "actor": actor, "victim": victim}

func strike(actor, region: String) -> void:
	actor.receive_located_hit(18.0, actor.global_position + Vector3(0, 0, -3), .5, false, actor.dismemberment.hit_point_for_region(region))

func world_bones(actor) -> PackedVector3Array:
	var result := PackedVector3Array()
	for name_value: String in ["Torso", "Chest", "Head", "Hand.L", "Hand.R"]:
		var bone: int = actor.skeleton.find_bone(name_value)
		result.append((actor.skeleton.global_transform * actor.skeleton.get_bone_global_pose(bone)).origin)
	return result

func skin_sample(actor) -> PackedVector3Array:
	var result := PackedVector3Array()
	for mesh: MeshInstance3D in actor.visual_meshes:
		if not mesh.visible: continue
		var baked: ArrayMesh = actor.dismemberment._bake_world_mesh(mesh, Vector3.ZERO)
		for surface in baked.get_surface_count():
			var vertices: PackedVector3Array = baked.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
			for vertex in range(0, vertices.size(), maxi(1, vertices.size() / 24)):
				result.append(vertices[vertex])
	return result

func maximum_displacement(before: PackedVector3Array, after: PackedVector3Array) -> float:
	if before.size() != after.size() or before.is_empty(): return INF
	var largest := 0.0
	for i in before.size(): largest = maxf(largest, before[i].distance_to(after[i]))
	return largest

func physical_sample(actor) -> Dictionary:
	var supported := false
	var max_speed := 0.0
	var weighted_energy := 0.0
	var mass := 0.0
	var maximum_core_y := -INF
	for entry: Dictionary in actor.ragdoll.pose_order:
		var body: RigidBody3D = entry.body
		max_speed = maxf(max_speed, body.linear_velocity.length())
		weighted_energy += body.mass * (body.linear_velocity.length_squared() + pow(float(entry.radius), 2) * body.angular_velocity.length_squared())
		mass += body.mass
		if str(entry.name) in ["Torso", "Chest", "Head"]:
			maximum_core_y = maxf(maximum_core_y, body.global_position.y)
			if body.contact_monitor:
				for contact: Node3D in body.get_colliding_bodies():
					if contact is PhysicsBody3D and (contact.collision_layer & 2) != 0:
						supported = true
	return {"core_supported": supported, "maximum_core_y": maximum_core_y, "max_speed": max_speed, "mean_energy": weighted_energy / maxf(mass, 1.0), "phase": actor.ragdoll.phase, "simulation_time": actor.ragdoll.simulation_time}

func pause_fall(actor) -> void:
	var body_positions: Array[Transform3D] = []
	for entry: Dictionary in actor.ragdoll.pose_order: body_positions.append(entry.body.global_transform)
	var phase: String = actor.knockdown_phase
	var clock: float = actor.ragdoll.simulation_time
	var pose := world_bones(actor)
	paused = true
	for frame in 5: await process_frame
	check(actor.knockdown_phase == phase and is_equal_approx(clock, actor.ragdoll.simulation_time), "pause freezes knockdown phase and physics clock")
	check(maximum_displacement(pose, world_bones(actor)) < .0001, "pause freezes the actual skin rig")
	for i in body_positions.size(): check(actor.ragdoll.pose_order[i].body.global_transform.is_equal_approx(body_positions[i]), "pause freezes articulated body transforms")
	paused = false

func ground_scenario(legs: Array) -> void:
	var f := fixture()
	var actor = f.actor
	var label := "+".join(legs)
	var defeats := [0]
	actor.defeated.connect(func(_actor): defeats[0] += 1)
	for frame in 3: await physics_frame
	var cut_pose := world_bones(actor)
	strike(actor, legs[0])
	check(not actor.is_knocked_down(), label + ": one ordinary non-severing hit does not fall")
	strike(actor, legs[0])
	check(actor.is_knocked_down() and actor.knockdown_phase == "falling", label + ": actual severance starts temporary physical fall")
	check(actor.ragdoll.temporary and actor.ragdoll.phase == "simulating", label + ": living limb loss uses real physics bodies")
	check(maximum_displacement(cut_pose, world_bones(actor)) < .45, label + ": severing does not snap directly into crawl")
	actor.set_physics_process(true)
	var before_root: Vector3 = actor.global_position
	var previous_bones := world_bones(actor)
	var last_skin := PackedVector3Array()
	var previous_physical := physical_sample(actor)
	var supported_frames := 0
	var recovery_seen := false
	var started_crawling := false
	var recovery_root := Vector3.ZERO
	var handoff_bones := INF
	var handoff_skin := INF
	var finish_bones := INF
	var recovery_samples: Array = []
	var pause_checked := false
	var removed_second := false
	var physical_states: Array = []
	for frame in 1200:
		var prior_phase: String = actor.knockdown_phase
		await physics_frame
		actor._resolve_active_attack()
		if frame == 8 and not pause_checked:
			await pause_fall(actor)
			pause_checked = true
		if legs.size() == 2 and frame == 12:
			strike(actor, legs[1]); strike(actor, legs[1])
			removed_second = true
			check(actor.is_knocked_down() and actor.ragdoll.temporary, label + ": second leg cut retains the in-flight living ragdoll")
			for bone: String in PARTS.REGION_BONES[legs[1]]:
				check(not actor.ragdoll.parts.has(bone), label + ": newly detached leg has no ghost physics body")
		var current_bones := world_bones(actor)
		if actor.knockdown_phase == "falling":
			check(actor.ragdoll.phase in ["simulating", "settled"], label + ": falling remains under physical pose control")
			check(Vector2(actor.velocity.x, actor.velocity.z).length() < .001, label + ": AI adds no chase velocity during fall")
			check(actor.global_position.distance_to(before_root) < .03, label + ": navigation body does not chase while physics falls")
			check(f.victim.contacts == 0, label + ": no attacks during fall")
			previous_physical = physical_sample(actor)
			supported_frames = supported_frames + 1 if previous_physical.core_supported else 0
			if previous_physical.core_supported and previous_physical.max_speed < .65:
				last_skin = skin_sample(actor)
			if frame % 30 == 0: physical_states.append(previous_physical)
		if prior_phase == "falling" and actor.knockdown_phase == "recovering":
			recovery_seen = true
			recovery_root = actor.global_position
			handoff_bones = maximum_displacement(previous_bones, current_bones)
			handoff_skin = maximum_displacement(last_skin, skin_sample(actor))
			check(previous_physical.core_supported and supported_frames >= 15, label + ": supported torso rest precedes pose recovery")
			check(previous_physical.maximum_core_y < .85, label + ": head and torso are down before recovery")
			check(previous_physical.max_speed < .65 and previous_physical.mean_energy < .08, label + ": physics stabilizes before animation takes over")
			check(handoff_bones < .12 and handoff_skin < .14, label + ": actual world bones and skin stay continuous across handoff")
			check(actor.crawl.blend < .08, label + ": recovery begins from solved world pose rather than completed crawl")
		if actor.knockdown_phase == "recovering":
			recovery_samples.append(actor.crawl.blend)
			check(actor.is_knocked_down(), label + ": recovery blend still blocks combat")
			check(actor.global_position.distance_to(recovery_root) < .03 and Vector2(actor.velocity.x, actor.velocity.z).length() < .001, label + ": root waits through pose recovery")
			check(f.victim.contacts == 0, label + ": blend cannot deal damage")
			check(maximum_displacement(previous_bones, current_bones) < .15, label + ": recovery pose progresses without per-frame jumps")
		if prior_phase == "recovering" and not actor.is_knocked_down():
			finish_bones = maximum_displacement(previous_bones, current_bones)
			check(actor.crawl.blend >= .999 and actor.ragdoll.phase == "living" and not actor.ragdoll.temporary, label + ": full blend restores living control")
			check(actor.ragdoll.parts.is_empty() and actor.ragdoll.joints.is_empty(), label + ": temporary articulated bodies fully released")
			check(finish_bones < .15, label + ": transition into crawl locomotion remains continuous")
			started_crawling = true
			break
		previous_bones = current_bones
	check(recovery_seen and started_crawling, label + ": supported living body finishes recovery")
	check(legs.size() == 1 or removed_second, label + ": two-leg scenario actually cuts again during fall")
	check(defeats[0] == 0 and actor.health > 0, label + ": knockdown neither kills nor grants reward")
	for i in range(1, recovery_samples.size()):
		check(recovery_samples[i] >= recovery_samples[i - 1], label + ": recovery never resets or reverses")
	if started_crawling:
		f.victim.global_position = actor.global_position + Vector3(0, 0, -4)
		var chase_start: Vector3 = actor.global_position
		for frame in 120:
			await physics_frame
			actor._resolve_active_attack()
		check(actor.global_position.distance_to(chase_start) > .20 and str(actor.animation_clip).begins_with("crawl"), label + ": recovered creature actually crawls toward player")
		f.victim.global_position = actor.global_position + Vector3(0, 0, -.8)
		for frame in 180:
			await physics_frame
			actor._resolve_active_attack()
		check(f.victim.contacts > 0 and actor.attack_index == 0, label + ": low bites resume after recovery")
	report.append({"legs": legs, "physical_states": physical_states, "handoff_bone_displacement": handoff_bones, "handoff_skin_displacement": handoff_skin, "recovery_blend": recovery_samples, "finish_displacement": finish_bones, "contacts": f.victim.contacts, "defeats": defeats[0]})
	f.world.queue_free()
	await process_frame

func airborne_scenario() -> void:
	var f := fixture(false, 40.0)
	var actor = f.actor
	strike(actor, "left_leg"); strike(actor, "left_leg")
	actor.set_physics_process(true)
	var start := world_bones(actor)
	for frame in 480:
		await physics_frame
		actor._resolve_active_attack()
	check(actor.is_knocked_down() and actor.knockdown_phase == "falling" and actor.ragdoll.temporary, "unsupported body does not recover through a timeout")
	check(actor.ragdoll.phase == "simulating" and actor.ragdoll.simulation_time > 7.0, "unsupported fixture really simulates beyond a fixed-delay fallback")
	check(not physical_sample(actor).core_supported and world_bones(actor)[0].y < start[0].y - 5.0, "no-floor case is genuine gravity-driven free fall")
	check(f.victim.contacts == 0 and actor.health > 0, "airborne living creature cannot attack")
	report.append({"case": "no_floor", "ragdoll": actor.ragdoll.snapshot(), "contacts": f.victim.contacts})
	f.world.queue_free()
	await process_frame

func fatal_during_fall() -> void:
	var f := fixture()
	var actor = f.actor
	var defeats := [0]
	actor.defeated.connect(func(_actor): defeats[0] += 1)
	strike(actor, "left_leg"); strike(actor, "left_leg")
	actor.set_physics_process(true)
	for frame in 12: await physics_frame
	var physics_ids := {}
	for name_value: String in actor.ragdoll.parts:
		physics_ids[name_value] = actor.ragdoll.parts[name_value].body.get_instance_id()
	var before := world_bones(actor)
	actor.receive_hit(10000, Vector3(0, .9, -3), .5, false)
	check(actor.ai_state == DungeonEnemy.AIState.DEAD and defeats[0] == 1, "fatal hit during fall kills and rewards exactly once")
	check(not actor.ragdoll.temporary and actor.ragdoll.phase in ["simulating", "settled"], "fatal hit upgrades existing physics without a second reaction")
	check(maximum_displacement(before, world_bones(actor)) < .02, "fatal upgrade preserves the in-flight solved pose")
	for name_value: String in physics_ids:
		check(actor.ragdoll.parts.has(name_value) and actor.ragdoll.parts[name_value].body.get_instance_id() == physics_ids[name_value], "fatal upgrade preserves the same connected body: " + name_value)
	for frame in 720:
		await physics_frame
		actor._resolve_active_attack()
		check(actor.ai_state == DungeonEnemy.AIState.DEAD and actor.knockdown_phase != "recovering", "dead fall never blends back into living crawl")
		if actor.ragdoll.phase == "settled": break
	check(actor.ragdoll.phase == "settled" and f.victim.contacts == 0, "upgraded corpse settles without returning to attacks")
	actor.receive_hit(10000, Vector3.ZERO, .5, false)
	check(defeats[0] == 1, "later corpse hit never grants another reward")
	report.append({"case": "fatal_during_fall", "ragdoll": actor.ragdoll.snapshot(), "defeats": defeats[0]})
	f.world.queue_free()
	await process_frame
