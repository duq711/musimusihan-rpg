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

var animation_player: AnimationPlayer
var skeleton: Skeleton3D
var attack_index := -1
var animation_clip := "idle"
var animation_sample := 0.0
var resolved_contacts := 0
var ragdoll: Node3D

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
	model_root = (load(MODEL_PATH) as PackedScene).instantiate()
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

func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for child in node.get_children():
		var found := _find_skeleton(child)
		if found != null:
			return found
	return null

func _physics_process(delta: float) -> void:
	state_time += delta
	if ai_state == AIState.DEAD:
		return
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
	resolved_contacts = 0
	if next_state == AIState.WINDUP:
		attack_index = (attack_index + 1) % ATTACKS.size()
	if is_instance_valid(animation_player):
		_update_visual_pose(0.0)

func _resolve_active_attack() -> void:
	if ai_state != AIState.ACTIVE:
		return
	var contacts: Array = CONTACTS[_attack()]
	while resolved_contacts < contacts.size() and state_time >= contacts[resolved_contacts]:
		resolved_contacts += 1
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
	if not is_instance_valid(animation_player):
		return
	if is_instance_valid(ragdoll) and ragdoll.phase != "living":
		return # The death reaction/physics controller exclusively owns the rig.
	var clip := "idle"
	var sample := state_time
	match ai_state:
		AIState.CHASE:
			clip = "walk"
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

func _die() -> void:
	if ai_state == AIState.DEAD:
		return
	ragdoll.begin(velocity)
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
	return {"archetype": "creep", "state": ai_state, "clip": animation_clip, "sample": animation_sample, "attack_index": attack_index, "resolved_contacts": resolved_contacts, "bones": skeleton.get_bone_count(), "meshes": visual_meshes.size(), "clips": animation_player.get_animation_list(), "source": MODEL_PATH, "ragdoll": ragdoll.snapshot()}
