extends SceneTree
## Use production input clocks, physical contacts and enemies in an isolated world.
const CREEP := preload("res://scripts/creep_enemy.gd")
const STEP := 1.0 / 60.0

var failures: Array[String] = []
var report: Array[Dictionary] = []
var viewport: SubViewport
var stage: Node3D
var player: DungeonPlayer
var bag: ExpeditionInventory
var actors: Array[DungeonEnemy] = []
var defeats := {}
var landed: Array[Dictionary] = []
var wall: StaticBody3D


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var original := ExpeditionSession.capture_snapshot()
	var original_items := _inventory_fingerprint(original.inventory)
	var cursor := Input.mouse_mode
	var initial_pause := paused
	var sandbox := root.get_node("TestRoomSandbox")
	sandbox.begin()
	paused = false
	_build_fixture()
	_test_catalog()
	_test_normal_purchase()
	_check(_equip("iron_dagger"), "catalog dagger must equip through the real bag API")
	if not str(bag.equipment.get("offhand", "")).is_empty():
		_check(bool(bag.unequip("offhand").accepted), "dagger fixture must support an empty offhand")
	_check(player.is_dagger_equipped(), "real equipment must select the dagger family")
	_check(is_equal_approx(player.get_melee_reach(), 1.05), "dagger reach must match its 1.05 world metre maximum blade-tip reach")
	_check(is_equal_approx(player.get_melee_hit_time(), 0.13), "dagger contact must occur at 130ms")
	_check(is_equal_approx(player.get_melee_active_duration(), 0.30), "dagger must have a 300ms active phase")
	_test_actual_visual_and_pose_boundaries()
	await _test_enemy_boundaries()
	await _test_perception(false)
	if CREEP.is_available():
		await _test_perception(true)
		await _test_creep_assassination()
	else:
		print("DAGGER ASSASSINATION: licensed Creep absent; its anatomical-contact/ragdoll checks SKIPPED")
	for scenario: String in ["rear", "front", "side", "wrong_weapon", "distance", "far_contact", "wall", "no_contact", "turn_before_contact"]:
		await _test_actual_strike(scenario)
	await _test_single_target()
	await _test_missed_contact_cannot_hit_late()
	await _test_equipment_changes()
	await _clear_targets()
	viewport.queue_free()
	await process_frame
	sandbox.finish()
	paused = initial_pause
	_check(ExpeditionSession.capture_snapshot() == original, "isolated dagger checks must restore the original expedition and inventory identity")
	_check(_inventory_fingerprint(original.inventory) == original_items, "dagger trials must preserve original item instances and equipment data")
	_check(Input.mouse_mode == cursor and paused == initial_pause, "dagger checks must preserve the desktop cursor and pause state")
	for failure in failures: push_error("DAGGER ASSASSINATION: " + failure)
	print("DAGGER ASSASSINATION REPORT: ", JSON.stringify(report))
	print("DAGGER ASSASSINATION TEST %s: real release/contact/recovery, Creep death without severing, rear geometry, actual LOS, perception, one target/defeat, equipment cancellation and preserved session" % ("PASS" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)


func _build_fixture() -> void:
	viewport = SubViewport.new()
	viewport.name = "DaggerAssassinationIsolatedWorld"
	viewport.size = Vector2i(640, 360)
	viewport.own_world_3d = true
	viewport.gui_disable_input = true
	viewport.physics_object_picking = false
	viewport.audio_listener_enable_3d = false
	root.add_child(viewport)
	stage = Node3D.new()
	viewport.add_child(stage)
	_add_box(Vector3(20.0, 0.2, 20.0), Vector3(0, -0.1, 0))
	bag = ExpeditionSession.get_inventory()
	player = DungeonPlayer.new()
	player.position = Vector3(0, 0.9, 1.1)
	player.set_physics_process(false)
	player.set_process_unhandled_input(false)
	player.bind_inventory(bag)
	stage.add_child(player)
	player.set_physics_process(false)
	player.set_process_unhandled_input(false)
	player.set_torch_enabled(false)
	player.attack_landed.connect(func(damage: float, headshot: bool): landed.append({"damage": damage, "headshot": headshot}))
	_check(viewport.own_world_3d and viewport.gui_disable_input and not player.is_physics_processing() and not player.is_processing_unhandled_input(), "fixture must use actual combat without sampling hardware input")


func _add_box(size: Vector3, position: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = DungeonEnemy.WORLD_LAYER
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	body.position = position
	stage.add_child(body)
	return body


func _spawn(creep: bool = false):
	var actor = CREEP.new() if creep else DungeonEnemy.new()
	actor.configure("단검 실제 판정 검증", 200.0, 21.0, 2.2, Color.GRAY)
	actor.position = Vector3(0, 0.9, 0)
	actor.set_physics_process(false)
	stage.add_child(actor)
	actor.set_physics_process(false)
	actor.setup(player, null, stage)
	actor.defeated.connect(_on_defeated)
	actors.append(actor)
	return actor


func _clear_targets() -> void:
	player.cancel_sword_attack()
	for actor in actors:
		if is_instance_valid(actor):
			actor.collision_layer = 0
			actor.get_parent().remove_child(actor)
			actor.queue_free()
	actors.clear()
	if is_instance_valid(wall):
		wall.get_parent().remove_child(wall)
		wall.queue_free()
	wall = null
	await physics_frame
	await process_frame


func _prepare_player(actor, offset: Vector3) -> void:
	player.cancel_sword_attack()
	player.stamina = player.MAX_STAMINA
	player.health = player.MAX_HEALTH
	player.velocity = Vector3.ZERO
	player.global_position = actor.global_position + offset
	player.look_at(Vector3(actor.global_position.x, player.global_position.y, actor.global_position.z), Vector3.UP)
	player.camera.position = Vector3.ZERO
	player.camera.rotation = Vector3.ZERO
	player.head.rotation = Vector3.ZERO
	var point: Vector3 = actor.global_position + Vector3(0, 0.2, 0)
	if actor.has_method("query_located_hit"):
		point = actor.dismemberment.hit_point_for_region("torso")
	player.head.look_at(point, Vector3.UP)
	player._pitch = player.head.rotation.x
	player._camera_shake = 0.0
	player._sword_draw_elapsed = player.SWORD_DRAW_DURATION
	player._update_viewmodel(0.0)


func _test_catalog() -> void:
	var item := ExpeditionInventory.get_item_definition("iron_dagger")
	_check(str(item.get("equip_slot", "")) == "weapon" and str(item.get("weapon_type", "")) == "melee" and str(item.get("weapon_family", "")) == "dagger", "dagger must be a real equipable melee weapon family")
	var entries := TestRoomCatalog.entries()
	for spec: Array in [["item:iron_dagger", "item", "iron_dagger"], ["dagger_assassination", "dagger_assassination", "rear"], ["dagger_assassination:front", "dagger_assassination", "front"]]:
		var matches: Array = entries.filter(func(entry: Dictionary): return str(entry.id) == spec[0])
		_check(matches.size() == 1, "one executable catalog entry: " + str(spec[0]))
		if matches.size() == 1:
			_check(str(matches[0].action) == spec[1] and str(matches[0].payload) == spec[2], "catalog action/payload must route actual trial: " + str(spec[0]))


func _test_normal_purchase() -> void:
	var stock := ExpeditionSession.get_stock_quantity("iron_dagger")
	var price := ExpeditionSession.get_buy_price("iron_dagger")
	var wallet := ExpeditionSession.crowns
	var count := bag.count_item("iron_dagger")
	_check(stock > 0 and price > 0, "ordinary merchant must actually stock and price the dagger")
	var result := ExpeditionSession.buy_item("iron_dagger")
	_check(bool(result.get("accepted", false)), "normal merchant transaction must sell the real dagger")
	_check(ExpeditionSession.crowns == wallet - price and bag.count_item("iron_dagger") == count + 1, "purchase must pay the real price and deliver one inventory item")
	_check(ExpeditionSession.get_stock_quantity("iron_dagger") == stock - 1, "normal finite dagger stock must decrease after purchase")
	_check(_equip("iron_dagger") and player.is_dagger_equipped(), "purchased dagger must equip through inventory and update actual player behavior")


func _test_actual_visual_and_pose_boundaries() -> void:
	player._sword_draw_elapsed = player.SWORD_DRAW_DURATION
	player._motion_equip_elapsed = 10.0
	player._motion_clock = 0.0
	player._motion_speed = 0.0
	player._motion_look_sway = Vector2.ZERO
	player.velocity = Vector3.ZERO
	player._update_viewmodel(0.0)
	_check(player.dagger_visual_root.is_visible_in_tree() and not player.sword_visual_root.is_visible_in_tree(), "equipping dagger must show the actual short mesh and hide the long sword")
	var blade := player.dagger_visual_root.get_node_or_null("PittedBlade") as MeshInstance3D
	_check(blade != null and blade.mesh != null and player.sword_blade == blade, "combat blade reference must point at the actual dagger geometry")
	if blade != null and blade.mesh != null:
		var axis := blade.global_basis.y.normalized()
		var lower := INF
		var upper := -INF
		var vertex_count := 0
		for surface in blade.mesh.get_surface_count():
			var arrays := blade.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			for vertex in vertices:
				var distance := (blade.global_transform * vertex).dot(axis)
				lower = minf(lower, distance)
				upper = maxf(upper, distance)
				vertex_count += 1
		_check(vertex_count > 12 and upper - lower > 0.30 and upper - lower < 0.34, "rendered dagger must contain a real roughly 32cm blade in world units")
		report.append({"case": "actual_dagger_mesh", "world_blade_length_m": upper - lower, "vertices": vertex_count})
	var boundaries: Array[Array] = [
		["windup_to_active", DungeonPlayer.CombatState.WINDUP, 0.10, DungeonPlayer.CombatState.ACTIVE, 0.0],
		["contact", DungeonPlayer.CombatState.ACTIVE, 0.13 - 0.00001, DungeonPlayer.CombatState.ACTIVE, 0.13 + 0.00001],
		["active_to_recovery", DungeonPlayer.CombatState.ACTIVE, 0.30, DungeonPlayer.CombatState.RECOVERY, 0.0],
		["recovery_to_ready", DungeonPlayer.CombatState.RECOVERY, 0.25, DungeonPlayer.CombatState.READY, 0.0],
	]
	for boundary: Array in boundaries:
		var before := _actual_weapon_pose(int(boundary[1]), float(boundary[2]))
		var after := _actual_weapon_pose(int(boundary[3]), float(boundary[4]))
		var distance := before.origin.distance_to(after.origin)
		var angle := 0.0 if before.basis.is_equal_approx(after.basis) else before.basis.get_rotation_quaternion().angle_to(after.basis.get_rotation_quaternion())
		_check(before.is_finite() and after.is_finite() and distance < 0.0005 and angle < 0.0015, "actual player dagger transform must remain continuous at " + str(boundary[0]))
		report.append({"case": boundary[0], "position_step_m": distance, "angle_step_deg": rad_to_deg(angle)})
	player.cancel_sword_attack()


func _actual_weapon_pose(state: int, elapsed: float) -> Transform3D:
	player._set_combat_state(state)
	player.state_time = elapsed
	player._update_viewmodel(0.0)
	return player.weapon_pivot.transform


func _test_enemy_boundaries() -> void:
	await _clear_targets()
	var actor = _spawn()
	await physics_frame
	for yaw: float in [0.0, 1.1, PI]:
		actor.rotation.y = yaw
		for angle: float in [-56.0, -54.0, 0.0, 54.0, 56.0, 90.0, 180.0]:
			var local := Vector3(sin(deg_to_rad(angle)), 0, cos(deg_to_rad(angle))) * 1.1
			var point: Vector3 = actor.global_position + actor.global_basis * local
			_check(actor.can_receive_dagger_assassination(point) == (absf(angle) <= 55.0), "rear cone must follow enemy local orientation (yaw %.2f, angle %.1f)" % [yaw, angle])
	actor.rotation = Vector3.ZERO
	for distance: float in [1.349, 1.351]:
		_check(actor.can_receive_dagger_assassination(actor.global_position + Vector3(0, 0, distance)) == (distance < 1.35), "assassination distance must use horizontal world metres")
	for height: float in [-1.251, -1.249, 1.249, 1.251]:
		_check(actor.can_receive_dagger_assassination(actor.global_position + Vector3(0, height, 1.1)) == (absf(height) < 1.25), "assassination cannot cross an excessive height difference")
	_prepare_player(actor, Vector3(0, 0, 1.1))
	actor.health = actor.max_health * 0.2
	actor._set_state(DungeonEnemy.AIState.STAGGER)
	_check(actor.begin_execution(player), "execution exclusion fixture must reserve a real vulnerable enemy")
	var reserved_health: float = actor.health
	var behind: Vector3 = actor.global_position + actor.global_basis.z * 1.1
	_check(not actor.can_receive_dagger_assassination(behind) and not actor.receive_dagger_assassination(behind), "an execution-reserved enemy cannot receive another assassination")
	_check(actor.health == reserved_health and _defeats(actor) == 0, "reserved enemy health and defeat transaction must remain unchanged")
	actor.cancel_execution(player)
	actor.health = actor.max_health
	actor._set_state(DungeonEnemy.AIState.IDLE)
	behind = actor.global_position + actor.global_basis.z * 1.1
	_check(actor.receive_dagger_assassination(behind), "validated rear receiver must use the existing death path")
	_check(actor.ai_state == DungeonEnemy.AIState.DEAD and _defeats(actor) == 1, "rear receiver must emit exactly one real defeat")
	_check(not actor.can_receive_dagger_assassination(behind) and not actor.receive_dagger_assassination(behind) and _defeats(actor) == 1, "dead target/repeated receiver must never issue a second defeat/reward signal")


func _test_perception(creep: bool) -> void:
	await _clear_targets()
	var actor = _spawn(creep)
	var archetype := "Creep" if creep else "warden"
	await physics_frame
	for angle: float in [0.0, 79.0, 81.0, 180.0]:
		# Angle measured from forward (-Z), unlike the assassination rear cone.
		player.global_position = actor.global_position + Vector3(sin(deg_to_rad(angle)), 0, -cos(deg_to_rad(angle))) * 2.5
		_check(actor._can_notice_target() == (angle < 80.0), archetype + " idle sight must use the forward 160-degree cone")
	player.global_position = actor.global_position + Vector3(0, 0, 1.1)
	actor._set_state(DungeonEnemy.AIState.IDLE)
	actor._physics_process(STEP)
	_check(actor.ai_state == DungeonEnemy.AIState.IDLE, archetype + " actual idle physics must not detect an unseen rear approach at dagger distance")
	player.global_position = actor.global_position + Vector3(0, 0, 0.6)
	_check(actor._can_notice_target(), archetype + " must still notice very close rear contact")
	player.global_position = actor.global_position + Vector3(0, 0, -2.5)
	actor._set_state(DungeonEnemy.AIState.IDLE)
	actor._physics_process(STEP)
	_check(actor.ai_state == DungeonEnemy.AIState.CHASE, archetype + " actual idle physics must acquire a visible frontal target")
	actor.rotation = Vector3.ZERO
	player.global_position = actor.global_position + Vector3(0, 0, 2.8)
	actor._set_state(DungeonEnemy.AIState.CHASE)
	actor._physics_process(STEP)
	_check(actor.ai_state == DungeonEnemy.AIState.CHASE, archetype + " already-alert pursuit must persist when the target moves behind")
	actor.rotation = Vector3.ZERO
	player.global_position = actor.global_position + Vector3(0, 0, -2.5)
	wall = _add_box(Vector3(3, 3, 0.16), actor.global_position + Vector3(0, 0.5, -1.2))
	await physics_frame
	_check(not actor._can_notice_target(), archetype + " vision must remain blocked by actual world collision")
	actor._set_state(DungeonEnemy.AIState.IDLE)
	actor._physics_process(STEP)
	_check(actor.ai_state == DungeonEnemy.AIState.IDLE, archetype + " actual idle physics must not acquire a target through the wall")


func _test_creep_assassination() -> void:
	await _clear_targets()
	_check(_equip("iron_dagger"), "Creep assassination fixture equips actual dagger")
	var creep = _spawn(true)
	_prepare_player(creep, Vector3(0, 0, 1.05))
	await physics_frame
	await physics_frame
	var hp: float = creep.health
	wall = _add_box(Vector3(2, 3, 0.15), creep.global_position + Vector3(0, 0.5, 0.53))
	await physics_frame
	_check(not _query_contains(creep) and player._located_melee_contact(creep, player.get_melee_reach()).is_empty(), "world wall must occlude both the anatomical ray and the Creep target query")
	if _begin_and_commit():
		_tick(player.get_melee_hit_time() + 0.001)
		_finish_attack()
	_check(creep.health == hp and _defeats(creep) == 0, "posed Creep anatomy cannot be assassinated through a wall")
	wall.get_parent().remove_child(wall)
	wall.queue_free()
	wall = null
	_prepare_player(creep, Vector3(0, 0, 1.05))
	await physics_frame
	var contact: Dictionary = player._located_melee_contact(creep, player.get_melee_reach())
	_check(not contact.is_empty(), "rear Creep kill must first intersect its actual posed anatomy")
	_check(_query_contains(creep) and player._has_clear_melee_path(creep), "rear Creep fixture needs production broad/contact query and clear path")
	var limb_hits: Dictionary = creep.dismemberment.hit_counts.duplicate(true)
	var limb_damage: Dictionary = creep.dismemberment.damage.duplicate(true)
	var before_hits := landed.size()
	if _begin_and_commit():
		_tick(0.129)
		_check(creep.health == hp and _defeats(creep) == 0, "full-health Creep must remain alive before the 130ms contact")
		_tick(0.002)
		_check(creep.health == 0.0 and creep.ai_state == DungeonEnemy.AIState.DEAD and _defeats(creep) == 1, "one real rear dagger contact must kill a full-health Creep")
		_check(creep.ragdoll.phase != "living", "dagger kill must enter the existing Creep ragdoll path")
		_check(creep.dismemberment.severed.is_empty() and creep.dismemberment.hit_counts == limb_hits and creep.dismemberment.damage == limb_damage, "assassination must not turn lethal damage into limb severing/region accumulation")
		_check(landed.size() == before_hits + 1, "assassination must emit one landed hit")
		_finish_attack()
		player._perform_melee_hit()
		_check(_defeats(creep) == 1 and landed.size() == before_hits + 1, "dead anatomy and repeated hit resolution must not reward twice")
		report.append({"case": "creep_rear", "health_before": hp, "health_after": creep.health, "defeats": _defeats(creep), "ragdoll": creep.ragdoll.phase, "anatomical_contact": contact.get("region", "")})


func _test_actual_strike(scenario: String) -> void:
	await _clear_targets()
	_check(_equip("rusted_sword" if scenario == "wrong_weapon" else "iron_dagger"), "actual strike must equip its requested weapon: " + scenario)
	var actor = _spawn()
	var offset := Vector3(0, 0, 1.05)
	if scenario == "front": offset = Vector3(0, 0, -1.05)
	if scenario == "side": offset = Vector3(1.05, 0, 0)
	if scenario == "distance": offset = Vector3(0, 0, 2.3)
	if scenario == "far_contact": offset = Vector3(0, 0, 1.60)
	_prepare_player(actor, offset)
	if scenario == "wall": wall = _add_box(Vector3(2, 3, 0.15), actor.global_position + Vector3(0, 0.5, 0.53))
	if scenario == "no_contact":
		player.head.look_at(player.camera.global_position + Vector3.RIGHT * 4.0, Vector3.UP)
	await physics_frame
	await physics_frame
	var no_hit := scenario in ["distance", "far_contact", "wall", "no_contact"]
	var hp: float = actor.health
	var hits_before := landed.size()
	var surface_contact_distance := -1.0
	if scenario == "far_contact":
		# Independently locate the real capsule surface inside the old 1.30m
		# query. The production short stab must miss this physical target.
		var from: Vector3 = player.camera.global_position
		var query := PhysicsRayQueryParameters3D.create(from, from - player.camera.global_basis.z * 1.30, DungeonEnemy.ENEMY_LAYER)
		var contact := stage.get_world_3d().direct_space_state.intersect_ray(query)
		_check(contact.get("collider") == actor, "far-contact fixture must intersect the actual enemy surface inside the former 1.30m reach")
		if not contact.is_empty():
			surface_contact_distance = from.distance_to(contact.position)
			_check(surface_contact_distance > 1.10 and surface_contact_distance < 1.30, "far-contact fixture must have measured first contact between 1.10m and 1.30m")
		_check(not _query_contains(actor), "production dagger query must exclude actual anatomy beyond its visible 1.05m blade-tip reach")
	if scenario in ["rear", "front", "side", "wrong_weapon", "turn_before_contact"]:
		_check(_query_contains(actor), "test must exercise a real candidate rather than an empty query: " + scenario)
	if scenario == "wall":
		_check(not _query_contains(actor) and not player._has_clear_melee_path(actor), "actual world collision must exclude the occluded dagger target")
	if scenario == "wrong_weapon":
		_check(not player.is_dagger_equipped() and player.get_melee_reach() >= 2.12, "ordinary sword retains its family and longer reach")
		_check(player.sword_visual_root.is_visible_in_tree() and not player.dagger_visual_root.is_visible_in_tree(), "switching back to sword must restore only its actual long-blade mesh")
	if _begin_and_commit():
		var expected_damage := player.get_melee_damage(player.attack_charge)
		if scenario == "turn_before_contact":
			actor.rotation.y = PI
		_tick(player.get_melee_hit_time() + 0.001)
		if scenario == "rear":
			_check(actor.health == 0.0 and _defeats(actor) == 1, "a real short rear stab must cause one immediate death")
		elif no_hit:
			_check(actor.health == hp and landed.size() == hits_before and _defeats(actor) == 0, "out-of-reach/occluded/missed stab must do no damage: " + scenario)
		else:
			_check(actor.health > 0.0 and actor.health < hp and _defeats(actor) == 0, "frontal/side/ordinary-sword contact must be ordinary damage: " + scenario)
			_check(hp - actor.health <= expected_damage * 1.421, "ordinary damage must not silently become a lethal assassination: " + scenario)
		var health_after: float = actor.health
		var hits_after := landed.size()
		_finish_attack()
		_check(actor.health == health_after and landed.size() == hits_after, "one committed strike must not repeat its damage: " + scenario)
		report.append({"case": scenario, "health_before": hp, "health_after": actor.health, "landed_hits": landed.size() - hits_before, "defeats": _defeats(actor), "surface_contact_distance_m": surface_contact_distance})


func _test_single_target() -> void:
	await _clear_targets()
	_check(_equip("iron_dagger"), "single-target check equips dagger")
	var first = _spawn()
	var second = _spawn()
	first.position.x = -0.15
	second.position.x = 0.15
	_prepare_player(first, Vector3(0.15, 0, 1.05))
	player.head.look_at(Vector3(0, 1.1, 0), Vector3.UP)
	await physics_frame
	await physics_frame
	_check(_isolated_ray_contains(first, second) and _isolated_ray_contains(second, first), "single-target fixture must place both actual capsules along the same short ray, checked independently")
	_check(player._query_melee_hits().size() == 1, "dagger production query must select the nearest one of the overlapping candidates")
	var before_hits := landed.size()
	if _begin_and_commit():
		_tick(player.get_melee_hit_time() + 0.001)
		var killed := int(first.health <= 0.0) + int(second.health <= 0.0)
		var untouched := int(first.health == first.max_health) + int(second.health == second.max_health)
		_check(killed == 1 and untouched == 1 and _defeats(first) + _defeats(second) == 1, "one dagger stab must kill only one real target, leaving the other untouched")
		_check(landed.size() == before_hits + 1, "single stab must emit exactly one landed hit with overlapping targets")
		_finish_attack()
		_check(_defeats(first) + _defeats(second) == 1, "remaining active time must not assassinate the second target")


func _test_equipment_changes() -> void:
	for phase: String in ["windup", "active"]:
		await _clear_targets()
		_check(_equip("iron_dagger"), "equipment boundary fixture equips dagger")
		var actor = _spawn()
		_prepare_player(actor, Vector3(0, 0, 1.05))
		await physics_frame
		var accepted := bool(player.begin_sword_attack("right_diagonal").get("accepted", false))
		_check(accepted, "equipment-change boundary must begin a real dagger windup")
		if not accepted: continue
		if phase == "active":
			player.attack_release_requested = true
			for step in range(40):
				if player.combat_state != DungeonPlayer.CombatState.WINDUP: break
				_tick(0.01)
			_check(player.combat_state == DungeonPlayer.CombatState.ACTIVE, "active equipment change must happen after the actual commit")
			_check(player.viewmodel_renderer.world_contact_enabled, "active dagger must use world depth at its real body contact")
		var stamina_after_commit := player.stamina
		var before_hits := landed.size()
		_check(_equip("rusted_sword"), "actual inventory swap must replace dagger with sword")
		_check(not player.is_dagger_equipped() and player.combat_state == DungeonPlayer.CombatState.READY, "equipment signal must synchronously cancel a pending stab: " + phase)
		_check(not player.viewmodel_renderer.world_contact_enabled, "weapon-change cancellation must restore normal viewmodel rendering: " + phase)
		player._commit_attack()
		_tick(1.0)
		_check(actor.health == actor.max_health and _defeats(actor) == 0 and landed.size() == before_hits, "cancelled dagger contact cannot arrive after a weapon swap: " + phase)
		_check(is_equal_approx(player.stamina, stamina_after_commit), "weapon swap must not refund or spend the already settled attack cost")
	await _clear_targets()
	_check(_equip("iron_dagger"), "empty slot boundary starts with dagger")
	_check(bool(bag.unequip("weapon").accepted), "dagger can be unequipped through inventory")
	_check(not player.is_dagger_equipped() and not bool(player.begin_sword_attack("right_diagonal").get("accepted", true)), "empty weapon slot cannot start a hidden dagger attack")


func _test_missed_contact_cannot_hit_late() -> void:
	await _clear_targets()
	_check(_equip("iron_dagger"), "missed-contact boundary equips dagger")
	var actor = _spawn()
	_prepare_player(actor, Vector3(0, 0, 1.05))
	var contact_position: Vector3 = actor.global_position
	actor.position.z -= 2.3
	await physics_frame
	_check(not _query_contains(actor), "first contact must genuinely miss an out-of-reach target")
	var before_hits := landed.size()
	if not _begin_and_commit(): return
	_tick(0.131)
	_check(actor.health == actor.max_health and landed.size() == before_hits, "the scheduled contact must miss without damage")
	actor.global_position = contact_position
	await physics_frame
	_check(_query_contains(actor) and actor.can_receive_dagger_assassination(player.global_position), "late target must really enter the rear assassination ray during withdrawal")
	_tick(0.04)
	player._resolve_active_attack()
	_finish_attack()
	_check(actor.health == actor.max_health and _defeats(actor) == 0 and landed.size() == before_hits, "a missed 130ms stab must not assassinate a new target during its remaining withdrawal window")


func _begin_and_commit() -> bool:
	var stamina_before := player.stamina
	var accepted := bool(player.begin_sword_attack("right_diagonal").get("accepted", false))
	_check(accepted, "production melee entry must accept the equipped short stab/sword")
	if not accepted: return false
	_check(player.stamina == stamina_before, "preparing a stab must not charge stamina before commit")
	player.attack_release_requested = true
	for step in range(40):
		if player.combat_state != DungeonPlayer.CombatState.WINDUP: break
		_tick(0.01)
	_check(player.combat_state == DungeonPlayer.CombatState.ACTIVE and is_zero_approx(player.state_time), "real LMB release must commit into the active phase at time zero")
	if player.is_dagger_equipped():
		_check(player.viewmodel_renderer.world_contact_enabled, "committed dagger must use real world depth during insertion")
	_check(is_equal_approx(player.stamina, stamina_before - player.get_melee_stamina_cost(player.attack_charge)), "real stab commit must spend its equipment-specific stamina once")
	return player.combat_state == DungeonPlayer.CombatState.ACTIVE


func _finish_attack() -> void:
	var stamina := player.stamina
	_tick(maxf(0.001, player.get_melee_active_duration() - player.state_time + 0.001))
	_check(player.combat_state == DungeonPlayer.CombatState.RECOVERY, "actual attack must recover after its active window")
	if player.is_dagger_equipped():
		_check(player.viewmodel_renderer.world_contact_enabled, "dagger withdrawal must retain actual world depth through recovery")
	_tick(0.70)
	_check(player.combat_state == DungeonPlayer.CombatState.READY and is_equal_approx(player.stamina, stamina), "recovery must return ready without a second attack cost")
	_check(not player.viewmodel_renderer.world_contact_enabled, "completed attack must restore the regular first-person render mode")


func _tick(delta: float) -> void:
	player.advance_action_timers(delta)
	player.advance_combat_state(delta, false)
	player._update_viewmodel(delta)
	player._resolve_active_attack()


func _query_contains(actor: DungeonEnemy) -> bool:
	for hit: Dictionary in player._query_melee_hits():
		if hit.get("collider") == actor: return true
	return false


func _isolated_ray_contains(actor: DungeonEnemy, excluded_actor: DungeonEnemy) -> bool:
	var from := player.camera.global_position
	var excluded: Array[RID] = [excluded_actor.get_rid()]
	var query := PhysicsRayQueryParameters3D.create(from, from - player.camera.global_basis.z * player.get_melee_reach(), DungeonEnemy.ENEMY_LAYER, excluded)
	query.collide_with_areas = false
	var hit := player.get_world_3d().direct_space_state.intersect_ray(query)
	return hit.get("collider") == actor


func _equip(item_id: String) -> bool:
	if str(bag.equipment.get("weapon", "")) == item_id: return true
	if bag.count_item(item_id) < 1 and bag.add_item(item_id) != 0: return false
	for index in bag.slots.size():
		if str(bag.slots[index].get("id", "")) == item_id:
			return bool(bag.equip_from_slot(index).get("accepted", false))
	return false


func _on_defeated(actor: DungeonEnemy) -> void:
	var id := actor.get_instance_id()
	defeats[id] = int(defeats.get(id, 0)) + 1


func _defeats(actor: DungeonEnemy) -> int:
	return int(defeats.get(actor.get_instance_id(), 0))


func _inventory_fingerprint(inventory: ExpeditionInventory) -> String:
	if inventory == null: return "no_inventory"
	return JSON.stringify({"slots": inventory.slots, "equipment": inventory.equipment, "equipment_data": inventory.equipment_data}).sha256_text()


func _check(condition: bool, message: String) -> void:
	if not condition: failures.append(message)
