extends "res://scripts/enemy.gd"
## Supplied orc skin and clips, driven by the existing enemy combat states.
## Damage, guard/parry, line of sight, rewards and extraction use DungeonEnemy.
const ORC_MODEL := preload("res://assets/3d/enemies/orc/orc.scn")
const ATTACKS := ["atack1", "atack2", "atack3"]
# Normalized source times: anticipation end, front-facing strike, follow-through.
# Measured against the supplied axe bone and inspected in actual GPU frames.
const STRIKE_TIMES := {"atack1": Vector3(.04,.11,.23), "atack2": Vector3(.48,.56,.64), "atack3": Vector3(.51,.59,.66)}
var animation_player: AnimationPlayer
var skeleton: Skeleton3D
var attack_index := -1
var animation_clip := "idle1"
var animation_sample := 0.0

func _build_body() -> void:
	collision_shape = CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.48
	capsule.height = 1.95
	collision_shape.shape = capsule
	collision_shape.position.y = 0.075
	add_child(collision_shape)
	visual_root = Node3D.new()
	visual_root.name = "OrcVisual"
	visual_root.position.y = -0.9
	# The supplied FBX faces +Z; the shared enemy AI faces -Z.
	visual_root.rotation.y = PI
	add_child(visual_root)
	visual_base_position = visual_root.position
	model_root = ORC_MODEL.instantiate()
	visual_root.add_child(model_root)
	animation_player = model_root.find_child("AnimationPlayer", true, false)
	skeleton = model_root.find_child("Skeleton3D", true, false)
	animation_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	_collect_visual_meshes(model_root)
	_prepare_flash_overlay()
	set_meta("enemy_archetype", "orc")
	_update_visual_pose(0.0)

func _physics_process(delta: float) -> void:
	if ai_state == AIState.DEAD:
		state_time += delta
		_update_visual_pose(delta)
		return
	super._physics_process(delta)

func _set_state(next_state: AIState, stagger_seconds: float = STAGGER_SECONDS) -> void:
	super._set_state(next_state, stagger_seconds)
	if next_state == AIState.WINDUP:
		attack_index = (attack_index + 1) % ATTACKS.size()
	if is_instance_valid(animation_player): _update_visual_pose(0.0)

func _update_weapon_pose(_delta: float) -> void:
	# Both supplied axes are skinned to their original hand/axe bones.
	# They are not the old sword's rigid pivot or sword-clash proxy.
	pass

func _update_visual_pose(_delta: float) -> void:
	if not is_instance_valid(animation_player): return
	var clip := "idle1"
	var sample := state_time
	match ai_state:
		AIState.CHASE:
			clip = "run" if move_speed > 2.0 else "walk"
		AIState.WINDUP, AIState.ACTIVE, AIState.RECOVERY:
			clip = ATTACKS[maxi(0, attack_index)]
			var length := animation_player.get_animation(clip).length
			var timing: Vector3 = STRIKE_TIMES[clip]
			if ai_state == AIState.WINDUP:
				sample = length * timing.x * clampf(state_time / 0.7, 0, 1)
			elif ai_state == AIState.ACTIVE:
				# The inherited single hit at .09 seconds lands at the visual strike.
				if state_time <= ATTACK_HIT_TIME: sample = length * lerpf(timing.x, timing.y, clampf(state_time / ATTACK_HIT_TIME, 0, 1))
				else: sample = length * lerpf(timing.y, timing.z, clampf((state_time - ATTACK_HIT_TIME) / (0.24 - ATTACK_HIT_TIME), 0, 1))
			else: sample = length * lerpf(timing.z, 1.0, clampf(state_time / 0.92, 0, 1))
		AIState.STAGGER:
			clip = "gethit"
			# The FBX contains two separate hit reactions. Use its first 1.5s take.
			sample = 1.5 * clampf(state_time / stagger_duration, 0, 1)
		AIState.DEAD:
			clip = "death"
	var animation := animation_player.get_animation(clip)
	if animation.loop_mode != Animation.LOOP_NONE: sample = fmod(sample, animation.length)
	else: sample = minf(sample, animation.length)
	if animation_player.current_animation != clip: animation_player.play(clip)
	animation_player.seek(sample, true)
	animation_clip = clip
	animation_sample = sample

func _die() -> void:
	_set_state(AIState.DEAD)
	velocity = Vector3.ZERO
	collision_layer = 0
	collision_mask = 0
	collision_shape.set_deferred("disabled", true)
	if flash_tween: flash_tween.kill()
	flash_material.albedo_color.a = 0.0
	flash_material.emission_energy_multiplier = 0.0
	# Keep the final supplied death pose; do not rotate the whole corpse sideways.
	defeated.emit(self)

func get_orc_snapshot() -> Dictionary:
	return {"archetype": "orc", "state": ai_state, "clip": animation_clip, "sample": animation_sample, "attack_index": attack_index, "bones": skeleton.get_bone_count(), "meshes": visual_meshes.size(), "clips": animation_player.get_animation_list(), "source": ORC_MODEL.resource_path}
