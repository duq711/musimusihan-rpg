extends SceneTree
## Check imported wound geometry and production severance effects together.
## Image quality is reviewed separately with the embedded rendering preview.

const CREEP := preload("res://scripts/creep_enemy.gd")
const PARTS := preload("res://scripts/creep_dismemberment.gd")
const EFFECT := preload("res://scripts/creep_wound_effect.gd")

var failures: Array[String] = []
var asset_checks_executed := false


func _init() -> void:
	call_deferred("run")


func check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
		push_error("CREEP WOUND: " + message)


func run() -> void:
	var cursor := Input.mouse_mode
	await effect_lifecycle()
	if CREEP.is_available() and ResourceLoader.exists(PARTS.MODEL_PATH):
		asset_checks_executed = true
		await production_wounds()
	else:
		print("CREEP WOUND ASSET CHECKS SKIPPED: install the licensed original and segmented model.")
	await test_room_trial()
	check(not paused, "test leaves the tree unpaused")
	check(Input.mouse_mode == cursor, "wound validation never captures the cursor")
	var coverage := "bounded emission, floor contact, pause, expiry, owner cleanup and test-room isolation/restoration"
	if asset_checks_executed:
		coverage += "; imported tissue depth, both cut surfaces, baked colors/UVs, hidden intact caps and no restored limbs"
	print("CREEP WOUND TEST ", "PASS" if failures.is_empty() else "FAIL", ": ", coverage, "; ", failures)
	quit(0 if failures.is_empty() else 1)


func floor_fixture() -> Node3D:
	var world := Node3D.new()
	root.add_child(world)
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 2
	world.add_child(floor_body)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(20, .2, 20)
	collision.shape = shape
	floor_body.add_child(collision)
	collision.position.y = -.1
	return world


func effect_lifecycle() -> void:
	var world := floor_fixture()
	await physics_frame
	var effect = EFFECT.new()
	world.add_child(effect)
	effect.configure(Vector3(0, 1.1, 0), Vector3(.3, .4, 1).normalized(), "left_arm")
	check(effect.droplets.size() > 0 and effect.droplets.size() <= EFFECT.DROPLET_COUNT, "one severance emits a bounded visible burst")
	check(effect.stains.size() <= EFFECT.MAX_STAINS, "initial stain count is bounded")
	check(effect.can_process(), "effect processes during active play")
	await physics_frame
	await process_frame
	var age_before: float = effect.age
	var transforms_before := transforms(effect)
	paused = true
	for frame in 8:
		await process_frame
	check(not effect.can_process(), "F2 tree pause suspends wound processing")
	check(effect.age == age_before, "pause freezes wound lifetime")
	check(transforms(effect) == transforms_before, "pause freezes blood droplets and stains")
	paused = false
	for frame in 150:
		await physics_frame
		if not is_instance_valid(effect):
			break
		check(effect.droplets.size() <= EFFECT.DROPLET_COUNT and effect.stains.size() <= EFFECT.MAX_STAINS, "ongoing simulation never exceeds its per-cut budget")
	check(is_instance_valid(effect), "floor traces remain briefly after the burst")
	if is_instance_valid(effect):
		check(effect.age > age_before, "effect resumes after unpausing")
		check(not effect.stains.is_empty(), "actual floor collision produces blood traces")
		for stain: MeshInstance3D in effect.stains:
			if not is_instance_valid(stain):
				continue
			check(stain.global_position.y >= -.005 and stain.global_position.y < .05, "blood trace rests on the raycast floor")
		# Start at the end of the real lifetime, then let normal tree processing
		# perform expiration. No wall-clock wait or manually invoked callback.
		effect.age = EFFECT.LIFETIME - .001
		for frame in 3:
			await physics_frame
		await process_frame
		check(not is_instance_valid(effect), "expired burst and blood traces are freed automatically")
	var owned_effect = EFFECT.new()
	world.add_child(owned_effect)
	owned_effect.configure(Vector3(0, 1, 0), Vector3.FORWARD, "head")
	world.queue_free()
	await process_frame
	check(not is_instance_valid(owned_effect), "trial replacement frees an active effect with its owner")


func transforms(node: Node) -> Dictionary:
	var result := {}
	for child: Node in node.get_children():
		if child is Node3D:
			result[child.get_instance_id()] = child.transform
		result.merge(transforms(child))
	return result


func production_wounds() -> void:
	var original_hash := FileAccess.get_sha256(CREEP.MODEL_PATH)
	var world := floor_fixture()
	var actor = CREEP.new()
	actor.position = Vector3(0, .9, 0)
	actor.health = 400
	actor.max_health = 400
	world.add_child(actor)
	actor.set_physics_process(false)
	for frame in 3:
		await physics_frame
	check(actor.dismemberment.enabled, "segmented model provides every wound surface")
	check(actor.dismemberment.snapshot().visual_effects == 0, "intact creature has no severance effects")
	for region: String in PARTS.REGIONS:
		for cap: MeshInstance3D in actor.dismemberment.body_caps[region] + actor.dismemberment.part_caps[region]:
			check(not cap.visible, "intact cap remains hidden: " + str(cap.name))
			check(cap.material_overlay == null, "wound surface excludes the bright hit flash")
			check(cap.get_active_material(0) == PARTS.WOUND_MATERIAL, "both wound surfaces use the tissue shader")
			check_cap_geometry(cap)
		check_opposing_interior(actor.dismemberment.body_caps[region], actor.dismemberment.part_caps[region], region)
	var cuts := 0
	for region: String in PARTS.REGIONS:
		strike(actor, region)
		check(actor.dismemberment.snapshot().visual_effects == cuts, "first localized hit cannot emit a severance burst: " + region)
		strike(actor, region)
		cuts += 1
		check(actor.dismemberment.snapshot().visual_effects == cuts, "successful cut emits exactly once: " + region)
		check(actor.dismemberment.detached.size() == cuts, "successful cut adds exactly one detached part: " + region)
		for mesh: MeshInstance3D in actor.dismemberment.meshes[region]:
			check(not mesh.visible, "cut anatomy is hidden on the surviving skin: " + region)
		for cap: MeshInstance3D in actor.dismemberment.body_caps[region]:
			check(cap.visible and cap.material_overlay == null, "body wound appears with its tissue material: " + region)
		for cap: MeshInstance3D in actor.dismemberment.part_caps[region]:
			check(not cap.visible, "source detached cap stays hidden on the living skeleton: " + region)
		check_baked_caps(actor.dismemberment, region)
	var effect_refs: Array = actor.dismemberment.wound_effects.duplicate()
	var detached_refs: Array = actor.dismemberment.detached.duplicate()
	actor.receive_hit(10.0, Vector3(0, .9, -3), .5, false)
	actor._flash_body()
	for frame in 6:
		await physics_frame
	check(actor.dismemberment.snapshot().visual_effects == cuts, "later corpse hits cannot replay the severance burst")
	for region: String in PARTS.REGIONS:
		for mesh: MeshInstance3D in actor.dismemberment.meshes[region]:
			check(not mesh.visible, "ragdoll and later hit flash never restore a severed part: " + region)
		for cap: MeshInstance3D in actor.dismemberment.body_caps[region]:
			check(cap.visible and cap.material_overlay == null and cap.get_active_material(0) == PARTS.WOUND_MATERIAL, "ragdoll preserves the body wound: " + region)
	world.queue_free()
	await process_frame
	for effect in effect_refs:
		check(not is_instance_valid(effect), "removing the encounter also removes each blood effect")
	for body in detached_refs:
		check(not is_instance_valid(body), "removing the encounter also removes each detached wound")
	check(FileAccess.get_sha256(CREEP.MODEL_PATH) == original_hash, "licensed original is unchanged")


func test_room_trial() -> void:
	var cursor := Input.mouse_mode
	ExpeditionSession.begin_new_journey()
	var original := ExpeditionSession.get_inventory()
	original.add_item("wooden_arrow", 7)
	ExpeditionSession.crowns = 73
	ExpeditionSession.hunger = 61.0
	var before := ExpeditionSession.capture_snapshot()
	var sandbox := root.get_node("TestRoomSandbox")
	var room = (load("res://test_room.tscn") as PackedScene).instantiate()
	root.add_child(room)
	current_scene = room
	await process_frame
	room.set_process(false)
	room.set_physics_process(false)
	room.player.set_physics_process(false)
	var matching: Array = room.feature_entries.filter(func(entry: Dictionary) -> bool: return entry.id == "creep_wound:head")
	check(matching.size() == 1, "test-room catalog registers one playable wound review")
	if matching.size() == 1:
		check(matching[0].action == "creep_wound" and matching[0].payload == "head", "wound review dispatches the actual head-severance path")
	check(sandbox.active and room.inventory != original, "wound review owns a separate test expedition")
	room.run_feature("creep_wound:head")
	var creep = find_creep(room)
	if not asset_checks_executed:
		check(creep == null and room.creep_dismemberment_timer == null, "missing asset cannot create a fake wound or pending cut")
		check(room.panel_open and paused and room.status_label.text.contains("설치"), "public clone gives paused asset-install guidance")
	else:
		check(creep != null, "wound review creates the production Creep")
		if creep != null:
			check(not paused and not room.panel_open, "wound review resumes the playable encounter")
			check(creep.dismemberment.snapshot().visual_effects == 0 and creep.dismemberment.severed.is_empty(), "review starts with an intact uninjured target")
			for frame in 160:
				if not creep.dismemberment.severed.is_empty():
					break
				await physics_frame
				await process_frame
			check(creep.dismemberment.severed == ["head"] and creep.dismemberment.snapshot().visual_effects == 1, "real trial timers cause one head cut and one blood effect")
			if not creep.dismemberment.wound_effects.is_empty():
				var effect = creep.dismemberment.wound_effects[0]
				await press_f2()
				var age: float = effect.age
				var frozen := transforms(effect)
				for frame in 8:
					await process_frame
				check(paused and room.panel_open and effect.age == age and transforms(effect) == frozen, "actual F2 review pause holds the burst and its lifetime")
				room.run_feature("creep_wound:head")
				var replacement = find_creep(room)
				await process_frame
				check(not is_instance_valid(effect) and not is_instance_valid(creep), "replaying review removes the previous body and blood effect")
				check(replacement != null and replacement.dismemberment.severed.is_empty() and replacement.dismemberment.snapshot().visual_effects == 0, "review replay starts with no retained wounds or emissions")
				room.reset_room()
				await process_frame
				check(find_creep(room) == null and room.creep_dismemberment_timer == null and room.panel_open and paused, "review reset cancels pending severance and restores the test menu")
	room.suspend_stress_effects()
	room.queue_free()
	current_scene = null
	paused = false
	await process_frame
	sandbox.finish()
	Input.mouse_mode = cursor
	check(ExpeditionSession.get_inventory() == original and ExpeditionSession.capture_snapshot() == before, "wound review returns the exact original expedition and inventory identity")


func find_creep(room: Node):
	for child: Node in room.get_children():
		if child is CREEP and not child.is_queued_for_deletion():
			return child
	return null


func press_f2() -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_F2
	event.physical_keycode = KEY_F2
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	event = event.duplicate() as InputEventKey
	event.pressed = false
	Input.parse_input_event(event)
	await process_frame


func strike(actor, region: String) -> void:
	var point: Vector3 = actor.dismemberment.hit_point_for_region(region)
	actor.receive_located_hit(18, Vector3(0, .9, -3), .5, region == "head", point)


func check_cap_geometry(cap: MeshInstance3D) -> void:
	var colors := {}
	var normal_directions := {}
	var vertices := PackedVector3Array()
	for surface in cap.mesh.get_surface_count():
		var arrays: Array = cap.mesh.surface_get_arrays(surface)
		var positions: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		vertices.append_array(positions)
		check(arrays[Mesh.ARRAY_COLOR] != null and arrays[Mesh.ARRAY_COLOR].size() == positions.size(), "every tissue vertex carries its color")
		check(arrays[Mesh.ARRAY_TEX_UV] != null and arrays[Mesh.ARRAY_TEX_UV].size() == positions.size(), "every tissue vertex carries detail UVs")
		if arrays[Mesh.ARRAY_COLOR] != null:
			for color: Color in arrays[Mesh.ARRAY_COLOR]:
				colors[color.to_rgba32()] = true
		for normal: Vector3 in arrays[Mesh.ARRAY_NORMAL]:
			check(normal.is_finite() and normal.length() > .9, "wound normal supports actual lit shading")
			normal_directions[normal.snapped(Vector3(.08, .08, .08))] = true
	check(colors.size() >= 8, "wound has varied tissue colors instead of a uniform pink fill")
	check(normal_directions.size() >= 6, "wound depth produces varied lit surface normals")
	check(vertices.size() >= 30, "wound contains interior tissue geometry")
	if vertices.size() >= 3:
		var origin := vertices[0]
		var longest := Vector3.ZERO
		for point: Vector3 in vertices:
			if (point - origin).length_squared() > longest.length_squared():
				longest = point - origin
		var normal := Vector3.ZERO
		for point: Vector3 in vertices:
			var candidate := longest.cross(point - origin)
			if candidate.length_squared() > normal.length_squared():
				normal = candidate
		normal = normal.normalized()
		var minimum := INF
		var maximum := -INF
		for point: Vector3 in vertices:
			var depth := (point - origin).dot(normal)
			minimum = minf(minimum, depth)
			maximum = maxf(maximum, depth)
		check(maximum - minimum > .003, "tissue is a recessed volume rather than a flat cap")


func check_opposing_interior(body_caps: Array, part_caps: Array, region: String) -> void:
	var body_points := {}
	var part_points := {}
	for collection: Array in [body_caps, part_caps]:
		var points: Dictionary = body_points if collection == body_caps else part_points
		for cap: MeshInstance3D in collection:
			for surface in cap.mesh.get_surface_count():
				for point: Vector3 in cap.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]:
					points[point.snapped(Vector3(.00001, .00001, .00001))] = true
	var distinct := 0
	for point: Vector3 in body_points:
		if not part_points.has(point):
			distinct += 1
	check(distinct >= 8, "body and detached cuts each have their own recessed interior: " + region)


func check_baked_caps(dismemberment, region: String) -> void:
	var body: RigidBody3D = dismemberment.detached.back()
	var found := 0
	for source: MeshInstance3D in dismemberment.part_caps[region]:
		var baked := body.get_node_or_null(NodePath(source.name)) as MeshInstance3D
		check(baked != null, "detached anatomy retains its opposing wound: " + region)
		if baked == null:
			continue
		found += 1
		check(baked.visible and baked.material_overlay == null, "released wound is visible without the living hit overlay")
		check(baked.mesh.get_surface_count() == source.mesh.get_surface_count(), "detached bake preserves every wound surface")
		for surface in baked.mesh.get_surface_count():
			var before: Array = source.mesh.surface_get_arrays(surface)
			var after: Array = baked.mesh.surface_get_arrays(surface)
			check(baked.get_active_material(surface) == PARTS.WOUND_MATERIAL, "released part keeps the same tissue shader")
			check(after[Mesh.ARRAY_COLOR] == before[Mesh.ARRAY_COLOR], "CPU skinning preserves tissue colors")
			check(after[Mesh.ARRAY_TEX_UV] == before[Mesh.ARRAY_TEX_UV], "CPU skinning preserves wound detail UVs")
			check(after[Mesh.ARRAY_BONES] == null and after[Mesh.ARRAY_WEIGHTS] == null, "released wound cannot be dragged by living bones")
	check(found > 0, "every detached part has an actual wound surface")
