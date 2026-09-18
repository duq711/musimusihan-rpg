extends "res://scripts/enemy.gd"
## CGTrader Creep: original skin/animation, existing damage/guard/reward rules.
## The licensed model is installed locally; public clones retain the warden.
const MODEL_PATH := "res://assets/licensed/creep/creep.glb"
const ATTACKS := ["bite", "punch"]
const WINDUPS := [0.82, 0.30]
const ACTIVE_TIMES := [0.30, 0.45]
const RECOVERIES := [0.48, 0.45]
const CONTACTS := [[0.18], [0.06, 0.34]]
const RAGDOLL := preload("res://scripts/creep_ragdoll.gd")
const DISMEMBERMENT := preload("res://scripts/creep_dismemberment.gd")
const CRAWL := preload("res://scripts/creep_crawl.gd")

var animation_player: AnimationPlayer
var skeleton: Skeleton3D
var attack_index := -1
var animation_clip := "idle"
var animation_sample := 0.0
var resolved_contacts := 0
var ragdoll: Node3D
var dismemberment: Node3D
var crawl: Node
var knockdown_phase := "none"
var _execution_entry_bones: Array[Transform3D] = []

static func is_available() -> bool:
	return ResourceLoader.exists(MODEL_PATH)

func _build_body() -> void:
	assert(is_available(), "Install the licensed Creep asset before instantiating it.")
	collision_shape = CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.43
	capsule.height = 1.80
	collision_shape.shape = capsule
	add_child(collision_shape)
	visual_root = Node3D.new()
	visual_root.name = "CreepVisual"
	visual_root.position.y = -0.90
	add_child(visual_root)
	visual_base_position = visual_root.position
	var installed_model := DISMEMBERMENT.MODEL_PATH if ResourceLoader.exists(DISMEMBERMENT.MODEL_PATH) else MODEL_PATH
	model_root = (load(installed_model) as PackedScene).instantiate()
	visual_root.add_child(model_root)
	animation_player = model_root.find_child("AnimationPlayer", true, false) as AnimationPlayer
	skeleton = _find_skeleton(model_root)
	assert(animation_player != null and skeleton != null)
	animation_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	_collect_visual_meshes(model_root)
	_prepare_flash_overlay()
	attack_range = 1.50
	set_meta("enemy_archetype", "creep")
	_update_visual_pose(0.0)
	ragdoll = RAGDOLL.new()
	ragdoll.name = "CreepRagdoll"
	add_child(ragdoll)
	ragdoll.configure(self, skeleton, animation_player)
	dismemberment = DISMEMBERMENT.new()
	dismemberment.name = "CreepDismemberment"
	add_child(dismemberment)
	dismemberment.configure(self, skeleton)
	crawl = CRAWL.new()
	crawl.name = "CreepCrawl"
	add_child(crawl)
	crawl.configure(self, skeleton)

func is_crawling() -> bool:
	return is_instance_valid(dismemberment) and dismemberment.missing_legs() > 0

func is_knocked_down() -> bool:
	return knockdown_phase != "none" and ai_state != AIState.DEAD

func _process_knockdown(delta: float) -> void:
	velocity = Vector3.ZERO
	if knockdown_phase == "falling":
		if ragdoll.temporary and ragdoll.phase == "settled":
			var fallen: Dictionary = ragdoll.take_recovery_pose()
			if fallen.is_empty():
				return
			var bones: Array = fallen.bones
			var hip: Vector3 = bones[skeleton.find_bone("Torso")].origin
			var offset: Vector3 = global_basis * crawl.prone[skeleton.find_bone("Torso")].origin
			# Re-anchor navigation under the physical landing, then restore every
			# world-space bone so the skin does not teleport with its root.
			global_position = Vector3(hip.x - offset.x, fallen.ground_point.y + .9, hip.z - offset.z)
			knockdown_phase = "recovering"
			crawl.begin_from_world_pose(bones)
	elif knockdown_phase == "recovering":
		crawl.apply(delta)
		if crawl.blend >= 1.0:
			knockdown_phase = "none"
			collision_shape.set_deferred("disabled", false)
			_set_state(AIState.CHASE if is_instance_valid(target) else AIState.IDLE)

func get_aim_point() -> Vector3:
	if is_crawling():
		return (skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone("Chest"))).origin
	return super.get_aim_point()

func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for child in node.get_children():
		var found := _find_skeleton(child)
		if found != null:
			return found
	return null

func _physics_process(delta: float) -> void:
	if ai_state == AIState.DEAD:
		return
	if is_knocked_down():
		_process_knockdown(delta)
		return
	if _process_execution_physics(delta):
		return
	state_time += delta
	if not is_on_floor():
		velocity.y -= gravity * delta
	var toward := Vector3.ZERO
	var distance := INF
	if is_instance_valid(target):
		toward = target.global_position - global_position
		toward.y = 0.0
		distance = toward.length()
	match ai_state:
		AIState.IDLE:
			_slow_down(delta)
			if distance <= detection_range and _has_line_of_sight():
				_set_state(AIState.CHASE)
		AIState.CHASE:
			if distance > detection_range * 1.55:
				_set_state(AIState.IDLE)
			elif distance <= attack_range and _has_line_of_sight():
				locked_attack_direction = toward.normalized()
				_set_state(AIState.WINDUP)
			else:
				_move_toward_target(toward, delta)
		AIState.WINDUP:
			_slow_down(delta)
			_face_direction(toward.normalized(), delta * 6.0)
			if state_time >= WINDUPS[_attack()]:
				locked_attack_direction = toward.normalized()
				_set_state(AIState.ACTIVE)
		AIState.ACTIVE:
			_slow_down(delta)
		AIState.RECOVERY:
			_slow_down(delta)
			if state_time >= RECOVERIES[_attack()]:
				# Do not insert a one-frame walking pose between adjacent attacks.
				if distance <= attack_range and _has_line_of_sight():
					locked_attack_direction = toward.normalized()
					_set_state(AIState.WINDUP)
				else:
					_set_state(AIState.CHASE)
		AIState.STAGGER:
			velocity.x = move_toward(velocity.x, 0.0, delta * 8.0)
			velocity.z = move_toward(velocity.z, 0.0, delta * 8.0)
			if state_time >= stagger_duration:
				if distance <= attack_range and _has_line_of_sight():
					locked_attack_direction = toward.normalized()
					_set_state(AIState.WINDUP)
				else:
					_set_state(AIState.CHASE)
	move_and_slide()
	_update_visual_pose(delta)

func _attack() -> int:
	return maxi(0, attack_index)

func _set_state(next_state: AIState, stagger_seconds: float = STAGGER_SECONDS) -> void:
	super._set_state(next_state, stagger_seconds)
	if next_state != AIState.EXECUTION:
		_execution_entry_bones.clear()
	resolved_contacts = 0
	if next_state == AIState.WINDUP:
		attack_index = (attack_index + 1) % ATTACKS.size()
		if is_crawling() or (is_instance_valid(dismemberment) and "left_arm" in dismemberment.severed and "right_arm" in dismemberment.severed):
			attack_index = 0 # Prone creatures keep supporting hands down and bite.
	if is_instance_valid(animation_player):
		_update_visual_pose(0.0)

func _resolve_active_attack() -> void:
	if ai_state != AIState.ACTIVE or is_knocked_down():
		return
	var contacts: Array = CONTACTS[_attack()]
	while resolved_contacts < contacts.size() and state_time >= contacts[resolved_contacts]:
		resolved_contacts += 1
		if _attack() == 1 and is_instance_valid(dismemberment):
			var attacking_arm := "right_arm" if resolved_contacts == 1 else "left_arm"
			if attacking_arm in dismemberment.severed:
				continue # A missing limb cannot deal an invisible punch.
		# One punch cycle has two contacts, sharing the original encounter damage.
		var full_damage := attack_damage
		attack_damage = full_damage / float(contacts.size())
		var connected := _attempt_attack()
		attack_damage = full_damage
		if ai_state != AIState.ACTIVE:
			return # Just guard interrupts the remaining contact.
		attack_has_connected = attack_has_connected or connected
	attack_has_resolved = resolved_contacts == contacts.size()
	if state_time >= ACTIVE_TIMES[_attack()]:
		_set_state(AIState.RECOVERY)

func _update_weapon_pose(_delta: float) -> void:
	pass # This creature is unarmed; no rigid sword or sword-clash proxy.

func _update_visual_pose(_delta: float) -> void:
	if not is_inside_tree() or not is_instance_valid(animation_player):
		return
	if is_instance_valid(ragdoll) and ragdoll.phase != "living":
		return # The death reaction/physics controller exclusively owns the rig.
	if knockdown_phase == "recovering":
		crawl.apply(_delta)
		return
	if ai_state == AIState.EXECUTION:
		_apply_execution_pose()
		return
	var clip := "idle"
	var sample := state_time
	match ai_state:
		AIState.CHASE:
			clip = "idle" if is_crawling() else "walk"
			# The source strides are in place; body travel uses the common AI.
			sample *= move_speed / 2.2
		AIState.WINDUP, AIState.ACTIVE, AIState.RECOVERY:
			clip = ATTACKS[_attack()]
			if ai_state == AIState.ACTIVE:
				sample += WINDUPS[_attack()]
			elif ai_state == AIState.RECOVERY:
				sample += WINDUPS[_attack()] + ACTIVE_TIMES[_attack()]
			sample = minf(sample, WINDUPS[_attack()] + ACTIVE_TIMES[_attack()] + RECOVERIES[_attack()])
		AIState.STAGGER:
			clip = "hit"
			sample = animation_player.get_animation(clip).length * clampf(state_time / stagger_duration, 0, 1)
		AIState.DEAD:
			clip = "death"
	var animation := animation_player.get_animation(clip)
	if clip in ["idle", "walk"]:
		sample = fmod(sample, animation.length)
	else:
		sample = minf(sample, animation.length)
	if animation_player.current_animation != clip:
		animation_player.play(clip)
	animation_player.seek(sample, true)
	animation_clip = clip
	animation_sample = sample
	if is_instance_valid(dismemberment):
		dismemberment.apply_living_pose(_delta)

func query_located_hit(from: Vector3, to: Vector3, radius: float = 0.0) -> Dictionary:
	return dismemberment.query_hit(from, to, radius) if is_instance_valid(dismemberment) else {}

func get_located_hit_attachment(hit_position: Vector3) -> Node3D:
	return dismemberment.create_attachment(hit_position)

func receive_located_hit(amount: float, attacker_position: Vector3, charge: float, headshot: bool, hit_position: Vector3) -> void:
	if ai_state == AIState.DEAD or amount <= 0.0 or not hit_position.is_finite():
		return
	if dismemberment.region_at_point(hit_position).is_empty():
		return # A stale contact on an absent limb is a miss, not torso damage.
	# Bake before the damage reaction seeks a different animation frame.
	var cut: String = dismemberment.register_hit(amount, hit_position, attacker_position)
	if not cut.is_empty() and ragdoll.is_knockdown_active():
		ragdoll.remove_severed_parts()
	if cut.ends_with("_leg") and health > amount and knockdown_phase != "falling":
		# Acquire the current pose before receive_hit can seek a standing recoil.
		if ragdoll.begin_knockdown(velocity):
			knockdown_phase = "falling"
			collision_shape.set_deferred("disabled", true)
			attack_index = 0
			resolved_contacts = 0
	if cut == "head":
		super.receive_hit(maxf(amount, health), attacker_position, charge, true)
	else:
		super.receive_hit(amount, attacker_position, charge, headshot)
	if is_knocked_down():
		velocity = Vector3.ZERO # Only physical parts may move during collapse.
	if not cut.is_empty() and hud:
		var labels := {"left_arm": "왼팔", "right_arm": "오른팔", "left_leg": "왼다리", "right_leg": "오른다리", "head": "머리"}
		hud.show_event("크리프 · %s 절단" % labels[cut], 1.0)

func get_execution_profile() -> String:
	return "crawl_stab" if is_crawling() else "shield_cut"

func is_execution_vulnerable() -> bool:
	if is_knocked_down():
		return false
	if is_crawling():
		return health > 0.0 and not is_queued_for_deletion() and ai_state != AIState.DEAD \
			and not is_instance_valid(_execution_executor) and ragdoll.phase == "living"
	return super.is_execution_vulnerable()

func begin_execution(executor: Node3D) -> bool:
	if not is_crawling():
		return super.begin_execution(executor)
	if not is_inside_tree() or not is_execution_vulnerable() or not _execution_executor_is_alive(executor):
		return false
	# Keep the actual prone orientation and all planted limbs. A crawler must
	# not swivel about its root or seek a standing reaction on reservation.
	_execution_executor = executor
	_execution_elapsed = 0.0
	_capture_execution_pose()
	velocity = Vector3.ZERO
	_set_state(AIState.EXECUTION)
	return true

func get_crawl_execution_contact() -> Vector3:
	var chest := get_aim_point()
	var start := chest + Vector3.UP * .8
	var end := chest - Vector3.UP * .25
	var nearest := INF
	var surface_point := chest
	# The hit capsules select anatomy during combat; the authored stab also
	# samples actual posed torso triangles once so its tip meets rendered skin.
	for part: MeshInstance3D in visual_meshes:
		if part.name != "CreepPart_torso" or not part.is_visible_in_tree():
			continue
		var baked: ArrayMesh = dismemberment._bake_world_mesh(part, Vector3.ZERO)
		var faces := baked.get_faces()
		for index in range(0, faces.size(), 3):
			var hit = Geometry3D.segment_intersects_triangle(start, end, faces[index], faces[index + 1], faces[index + 2])
			if hit is Vector3 and start.distance_squared_to(hit) < nearest:
				nearest = start.distance_squared_to(hit)
				surface_point = hit
	set_meta("execution_contact_on_skin", nearest < INF)
	if nearest < INF:
		return surface_point
	var fallback := query_located_hit(start, end)
	return fallback.get("position", chest)

func _capture_execution_pose() -> void:
	super._capture_execution_pose()
	_execution_entry_bones.clear()
	if is_instance_valid(skeleton):
		for bone in skeleton.get_bone_count():
			_execution_entry_bones.append(skeleton.get_bone_pose(bone))

func _apply_execution_pose() -> void:
	if not is_instance_valid(animation_player) or not is_instance_valid(skeleton):
		return
	if is_instance_valid(ragdoll) and ragdoll.phase != "living":
		return
	if is_crawling() and is_instance_valid(crawl):
		if _execution_entry_bones.size() == skeleton.get_bone_count():
			for bone in skeleton.get_bone_count():
				skeleton.set_bone_pose(bone, _execution_entry_bones[bone])
		animation_clip = "crawl_execution_stab"
		return
	var press := smoothstep(0.0, EXECUTION_SHIELD_SECONDS, _execution_elapsed)
	var kneel := smoothstep(EXECUTION_SHIELD_SECONDS, EXECUTION_CUT_START_SECONDS, _execution_elapsed)
	var cut := smoothstep(EXECUTION_CUT_START_SECONDS, EXECUTION_HIT_SECONDS, _execution_elapsed)
	var entry_blend := smoothstep(0.0, 0.12, _execution_elapsed)
	var hit := animation_player.get_animation("hit")
	# Sample the real source recoil without allowing its return-to-idle section.
	var sample := hit.length * (0.28 * press + 0.12 * kneel + 0.08 * cut)
	if animation_player.current_animation != "hit":
		animation_player.play("hit")
	animation_player.seek(sample, true)
	if _execution_entry_bones.size() == skeleton.get_bone_count():
		for bone in skeleton.get_bone_count():
			var recoil := skeleton.get_bone_pose(bone)
			skeleton.set_bone_pose(bone, _execution_entry_bones[bone].interpolate_with(recoil, entry_blend))
	var lowered := visual_base_position + Vector3(0.025 * cut, -0.13 * kneel, 0.08 * press)
	visual_root.position = _execution_entry_visual.origin.lerp(lowered, entry_blend)
	visual_root.rotation = _execution_entry_visual.basis.get_euler() + _degrees(Vector3(-7.0 * press + 15.0 * kneel + 6.0 * cut, 0.0, 5.0 * cut)) * entry_blend
	animation_clip = "hit"
	animation_sample = sample

func _die() -> void:
	if ai_state == AIState.DEAD:
		return
	ragdoll.begin(velocity)
	knockdown_phase = "none"
	_set_state(AIState.DEAD)
	velocity = Vector3.ZERO
	collision_layer = 0
	collision_mask = 0
	collision_shape.set_deferred("disabled", true)
	if flash_tween:
		flash_tween.kill()
	flash_material.albedo_color.a = 0.0
	flash_material.emission_energy_multiplier = 0.0
	defeated.emit(self)

func get_creep_snapshot() -> Dictionary:
	return {"archetype": "creep", "knockdown_phase": knockdown_phase, "state": ai_state, "clip": animation_clip, "sample": animation_sample, "attack_index": attack_index, "resolved_contacts": resolved_contacts, "bones": skeleton.get_bone_count(), "meshes": visual_meshes.size(), "clips": animation_player.get_animation_list(), "source": MODEL_PATH, "ragdoll": ragdoll.snapshot(), "dismemberment": dismemberment.snapshot(), "crawl": crawl.snapshot()}
