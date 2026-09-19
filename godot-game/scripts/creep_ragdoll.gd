extends Node3D
## Real rigid-body ragdoll, explicit connections for the imported Creep IK rig.
## Death and temporary leg-loss falls share the same solved physical rig.
const POSE_DRIVER := preload("res://scripts/creep_ragdoll_pose.gd")
const REACTION_SECONDS := 0.18
const WORLD_LAYER := 2
const CORPSE_LAYER := 32
const SETTLE_SPEED := 0.50
const SETTLE_MEAN_SQUARED_SPEED := 0.018
const SETTLE_HOLD := 0.60
const KNOCKDOWN_SETTLE_HOLD := 0.35
const GROUND_NORMAL_DOT := 0.65
const CORE_PARTS := ["Torso", "Chest", "Head"]

# bone, endpoint, parent body, radius(m), mass(kg), extra endpoint length(m).
const PARTS := [
	["Torso", "Chest", "", .16, 10.0, 0.0],
	["Chest", "Neck", "Torso", .22, 14.0, 0.0],
	["Neck", "Head", "Chest", .14, 3.0, 0.0],
	["Head", "", "Neck", .235, 6.0, .18],
	["Shoulder.L", "Arm1.L", "Chest", .105, 2.0, 0.0],
	["Arm1.L", "Arm2.L", "Shoulder.L", .10, 3.0, 0.0],
	["Arm2.L", "Hand.L", "Arm1.L", .072, 2.0, 0.0],
	["Hand.L", "FingB1.L", "Arm2.L", .068, 1.0, .12],
	["Shoulder.R", "Arm1.R", "Chest", .105, 2.0, 0.0],
	["Arm1.R", "Arm2.R", "Shoulder.R", .10, 3.0, 0.0],
	["Arm2.R", "Hand.R", "Arm1.R", .072, 2.0, 0.0],
	["Hand.R", "FingB1.R", "Arm2.R", .068, 1.0, .12],
	["Leg1.L", "Leg2.L", "Torso", .12, 6.0, 0.0],
	["Leg2.L", "Leg3.L", "Leg1.L", .088, 3.0, 0.0],
	["Leg3.L", "Foot.L", "Leg2.L", .060, 1.5, 0.0],
	["Foot.L", "StepA1.L", "Leg3.L", .070, 1.0, .10],
	["Leg1.R", "Leg2.R", "Torso", .12, 6.0, 0.0],
	["Leg2.R", "Leg3.R", "Leg1.R", .088, 3.0, 0.0],
	["Leg3.R", "Foot.R", "Leg2.R", .060, 1.5, 0.0],
	["Foot.R", "StepA1.R", "Leg3.R", .070, 1.0, .10],
]

var phase := "living"
var actor: Node3D
var rig: Skeleton3D
var player: AnimationPlayer
var driver: SkeletonModifier3D
var parts: Dictionary = {}
var pose_order: Array[Dictionary] = []
var joints: Array[Joint3D] = []
var initial_pose: Array[Transform3D] = []
var impact_velocity := Vector3.ZERO
var reaction_time := 0.0
var simulation_time := 0.0
var quiet_time := 0.0
var temporary := false
var ground_supported := false
var core_low := false
var ground_point := Vector3.ZERO
var support_parts: Array[String] = []
var mean_squared_speed := 0.0
var support_normals: Array[Vector3] = []
var settled_evidence: Dictionary = {}
var execution_owner: Node3D
var execution_release_reason := ""

func configure(owner_actor: Node3D, skeleton: Skeleton3D, animation: AnimationPlayer) -> void:
	actor = owner_actor
	rig = skeleton
	player = animation
	driver = POSE_DRIVER.new()
	driver.name = "CreepPhysicsPose"
	driver.controller = self
	rig.add_child(driver)
	driver.active = false
	set_physics_process(false)

func begin(death_velocity: Vector3, hold_for_executor: Node3D = null) -> void:
	if temporary and phase in ["simulating", "settled"]:
		# A fatal hit during a living fall kills this physical body in place.
		# No standing reaction, duplicate bodies, or pending recovery survives it.
		temporary = false
		remove_severed_parts()
		actor.animation_clip = "ragdoll"
		return
	if phase != "living":
		return
	temporary = false
	reaction_time = 0.0
	simulation_time = 0.0
	quiet_time = 0.0
	ground_supported = false
	core_low = false
	support_parts.clear()
	support_normals.clear()
	settled_evidence.clear()
	initial_pose.clear()
	for bone in rig.get_bone_count():
		initial_pose.append(rig.get_bone_pose(bone))
	execution_owner = hold_for_executor
	execution_release_reason = ""
	if is_instance_valid(execution_owner):
		# Death/reward is already committed, but the embedded blade still supports
		# the final contraction. No physical bodies can fall before withdrawal.
		impact_velocity = Vector3.ZERO
		phase = "execution_hold"
		actor.animation_clip = "crawl_execution_stab"
		set_physics_process(true)
		return
	impact_velocity = death_velocity.limit_length(3.2)
	if impact_velocity.length_squared() < .01:
		impact_velocity = actor.global_basis.z.normalized() * 1.2
	phase = "reaction"
	actor.animation_clip = "hit"
	actor.animation_sample = 0.0
	set_physics_process(true)

func begin_knockdown(fall_velocity: Vector3) -> bool:
	if phase != "living" or actor.ai_state == DungeonEnemy.AIState.DEAD:
		return false
	temporary = true
	reaction_time = 0.0
	simulation_time = 0.0
	quiet_time = 0.0
	ground_supported = false
	core_low = false
	support_parts.clear()
	support_normals.clear()
	settled_evidence.clear()
	impact_velocity = fall_velocity.limit_length(3.2)
	if impact_velocity.length_squared() < .01:
		impact_velocity = actor.global_basis.z.normalized() * 1.2
	# The amputated pose is sampled before any hit/crawl animation can replace it.
	_start_physics()
	set_physics_process(true)
	return true

func is_knockdown_active() -> bool:
	return temporary and phase in ["simulating", "settled"]

func release_execution_hold(executor: Node3D, reason := "blade_clear") -> bool:
	if phase != "execution_hold" or not is_instance_valid(executor) or executor != execution_owner:
		return false
	_release_execution_hold(reason)
	return true

func _release_execution_hold(reason: String) -> void:
	# Hand the exact held pose straight to gravity; do not play another hit
	# reaction or add the ordinary death impulse after the blade is removed.
	execution_owner = null
	execution_release_reason = reason
	# Reset/pooling can detach a target before cancelling the player's action.
	# Avoid building world-space physics off-tree or on a queued corpse. If a
	# pooled body returns, the active controller releases it on its next tick.
	if not is_inside_tree() or not actor.is_inside_tree() or actor.is_queued_for_deletion():
		return
	_start_physics()

func _physics_process(delta: float) -> void:
	if phase == "execution_hold":
		for bone in rig.get_bone_count(): rig.set_bone_pose(bone, initial_pose[bone])
		# Cancellation normally releases explicitly. This also covers a removed
		# executor or interrupted scene lifecycle without leaving a frozen corpse.
		if not is_instance_valid(execution_owner) or not actor._execution_executor_is_alive(execution_owner) \
				or (execution_owner is DungeonPlayer and not execution_owner.is_execution_active()):
			_release_execution_hold(execution_release_reason if not execution_release_reason.is_empty() else "executor_unavailable")
	elif phase == "reaction":
		reaction_time = minf(reaction_time + delta, REACTION_SECONDS)
		if actor.is_crawling():
			# Never blend a prone death back into the standing source hit clip.
			for bone in rig.get_bone_count(): rig.set_bone_pose(bone, initial_pose[bone])
		else:
			player.play("hit")
			player.seek(reaction_time * 1.25, true)
			var blend := smoothstep(0.0, REACTION_SECONDS, reaction_time)
			for bone in rig.get_bone_count():
				var hit := rig.get_bone_pose(bone)
				rig.set_bone_pose(bone, initial_pose[bone].interpolate_with(hit, blend))
		actor.animation_sample = reaction_time * 1.25
		if reaction_time >= REACTION_SECONDS:
			_start_physics()
	elif phase == "simulating":
		simulation_time += delta
		# SkeletonModifier3D output is transient during skin rendering. Persist
		# the solved pose for physics-time damage queries and the recovery handoff.
		driver.call("apply_physical_pose")
		var quiet := true
		var energy := 0.0
		var total_mass := 0.0
		var supported := false
		for entry: Dictionary in pose_order:
			var body: RigidBody3D = entry.body
			quiet = quiet and (body.sleeping or body.linear_velocity.length() < SETTLE_SPEED)
			energy += body.mass * (body.linear_velocity.length_squared() + pow(float(entry.radius), 2) * body.angular_velocity.length_squared())
			total_mass += body.mass
			if body.contact_monitor:
				for contact: Node3D in body.get_colliding_bodies():
					if contact is PhysicsBody3D and (contact.collision_layer & WORLD_LAYER) != 0:
						supported = true
			if simulation_time > 4.0:
				body.linear_damp = 1.5
				body.angular_damp = 3.0
		var slow_parts := quiet
		mean_squared_speed = energy / maxf(total_mass, 1.0)
		quiet = quiet and mean_squared_speed < SETTLE_MEAN_SQUARED_SPEED
		_read_ground_support()
		if temporary:
			# Feet/arms hitting a wall or a short timer cannot authorize recovery.
			# The torso must be down and actual upward core contacts must stay quiet.
			quiet_time = quiet_time + delta if quiet and ground_supported and core_low else 0.0
			if quiet_time >= KNOCKDOWN_SETTLE_HOLD:
				_settle()
		else:
			quiet_time = quiet_time + delta if quiet and supported and simulation_time > 1.0 else maxf(0.0, quiet_time - delta * 2.0)
			if quiet_time >= SETTLE_HOLD:
				_settle()
			elif simulation_time > 6.0 and supported and slow_parts and mean_squared_speed < .08:
				_settle() # Bound small solver jitter on a supported corpse, never mid-air.

func _read_ground_support() -> void:
	support_parts.clear()
	support_normals.clear()
	ground_supported = false
	core_low = false
	var support_sum := Vector3.ZERO
	var contact_count := 0
	for name_value: String in CORE_PARTS:
		if not parts.has(name_value):
			continue
		var body: RigidBody3D = parts[name_value].body
		var state := PhysicsServer3D.body_get_direct_state(body.get_rid())
		if state == null:
			continue
		for contact in state.get_contact_count():
			var collider = state.get_contact_collider_object(contact)
			if not collider is PhysicsBody3D or (collider.collision_layer & WORLD_LAYER) == 0:
				continue
			# Godot's contact "local normal" refers to this body's contact side;
			# the vector, like contact positions, is already in WORLD coordinates.
			var normal := state.get_contact_local_normal(contact).normalized()
			if normal.dot(Vector3.UP) < GROUND_NORMAL_DOT:
				continue
			if name_value not in support_parts:
				support_parts.append(name_value)
			support_normals.append(normal)
			support_sum += state.get_contact_collider_position(contact)
			contact_count += 1
	if contact_count == 0:
		return
	ground_point = support_sum / float(contact_count)
	# At least one load-bearing core body must actually contact the floor.
	# Head contact alone while the hips are still standing cannot qualify.
	ground_supported = "Torso" in support_parts or "Chest" in support_parts
	core_low = ground_supported
	for name_value: String in CORE_PARTS:
		if not parts.has(name_value):
			continue
		var height: float = parts[name_value].body.global_position.y - ground_point.y
		var maximum := .58 if name_value == "Torso" else (.68 if name_value == "Chest" else .78)
		core_low = core_low and height >= -.12 and height < maximum

func _bone_world(name_value: String) -> Transform3D:
	var index := rig.find_bone(name_value)
	assert(index >= 0, "Creep ragdoll bone missing: " + name_value)
	return rig.global_transform * rig.get_bone_global_pose(index)

func _axis_basis(y_axis: Vector3) -> Basis:
	var y := y_axis.normalized()
	var guide := Vector3.RIGHT if absf(y.dot(Vector3.UP)) > .9 else Vector3.UP
	var x := guide.cross(y).normalized()
	return Basis(x, y, x.cross(y).normalized())

func _start_physics() -> void:
	# Bodies use world metres, never the GLB root's 0.351 import scale.
	set_as_top_level(true)
	global_transform = Transform3D.IDENTITY
	for spec: Array in PARTS:
		if is_instance_valid(actor.get("dismemberment")) and actor.dismemberment.is_bone_severed(spec[0]):
			continue # Already detached geometry has its own independent body.
		var bone_world := _bone_world(spec[0])
		var start := bone_world.origin
		var end: Vector3 = _bone_world(spec[1]).origin if not str(spec[1]).is_empty() else start + bone_world.basis.y.normalized() * float(spec[5])
		if not str(spec[1]).is_empty():
			end += start.direction_to(end) * float(spec[5])
		var length := start.distance_to(end)
		var radius: float = spec[3]
		var body := RigidBody3D.new()
		body.name = str(spec[0]).replace(".", "_")
		body.mass = spec[4]
		body.collision_layer = CORPSE_LAYER
		body.collision_mask = WORLD_LAYER | CORPSE_LAYER
		body.freeze = true
		body.continuous_cd = true
		body.linear_damp = .35
		body.angular_damp = 1.5
		body.can_sleep = true
		body.contact_monitor = str(spec[0]) in ["Torso", "Chest", "Head", "Foot.L", "Foot.R"]
		body.max_contacts_reported = 8 if body.contact_monitor else 0
		var material := PhysicsMaterial.new()
		material.friction = .85
		material.bounce = 0.0
		body.physics_material_override = material
		add_child(body)
		body.global_transform = Transform3D(_axis_basis(end - start), (start + end) * .5)
		var collision := CollisionShape3D.new()
		var shape := CapsuleShape3D.new()
		shape.radius = radius
		shape.height = maxf(radius * 2.0, length + radius * .55)
		collision.shape = shape
		body.add_child(collision)
		var entry := {"body": body, "bone": rig.find_bone(spec[0]), "name": spec[0], "parent": spec[2], "start": start, "end": end, "radius": radius, "body_to_bone": body.global_transform.affine_inverse() * bone_world}
		parts[spec[0]] = entry
		pose_order.append(entry)
	for entry: Dictionary in pose_order:
		if not str(entry.parent).is_empty() and parts.has(entry.parent):
			_create_joint(entry, parts[entry.parent])
	# Ignore connected and initially overlapping parts; remaining limbs collide.
	# This avoids explosions from the original hunched shoulders/neck overlap.
	for a in pose_order.size():
		for b in range(a + 1, pose_order.size()):
			var first := pose_order[a]
			var second := pose_order[b]
			var closest := Geometry3D.get_closest_points_between_segments(first.start, first.end, second.start, second.end)
			if first.parent == second.name or second.parent == first.name or closest[0].distance_to(closest[1]) < float(first.radius) + float(second.radius) + .04:
				first.body.add_collision_exception_with(second.body)
				second.body.add_collision_exception_with(first.body)
	pose_order.sort_custom(func(a: Dictionary, b: Dictionary): return _bone_depth(a.bone) < _bone_depth(b.bone))
	phase = "simulating"
	actor.animation_clip = "ragdoll"
	driver.active = true
	for entry: Dictionary in pose_order:
		var body: RigidBody3D = entry.body
		body.freeze = false
		body.linear_velocity = impact_velocity * .55
	# A small off-centre upper-body impulse gives impact direction without flight.
	var chest: RigidBody3D = parts.Chest.body
	chest.apply_impulse(impact_velocity * 3.0, Vector3(0, .13, 0))

func _bone_depth(index: int) -> int:
	var depth := 0
	while rig.get_bone_parent(index) >= 0:
		depth += 1
		index = rig.get_bone_parent(index)
	return depth

func _create_joint(entry: Dictionary, parent: Dictionary) -> void:
	var bone_name: String = entry.name
	entry.parent_anchor = parent.body.global_transform.affine_inverse() * entry.start
	var hinge := bone_name.begins_with("Arm2") or bone_name.begins_with("Leg2") or bone_name.begins_with("Leg3")
	var joint: Joint3D
	if hinge:
		var h := HingeJoint3D.new()
		h.set_flag(HingeJoint3D.FLAG_USE_LIMIT, true)
		h.set_param(HingeJoint3D.PARAM_LIMIT_LOWER, -.35)
		h.set_param(HingeJoint3D.PARAM_LIMIT_UPPER, 1.35 if not bone_name.begins_with("Leg3") else .65)
		joint = h
	else:
		var cone := ConeTwistJoint3D.new()
		cone.swing_span = deg_to_rad(55 if bone_name.begins_with("Arm1") or bone_name.begins_with("Leg1") else 30)
		cone.twist_span = deg_to_rad(35 if bone_name.begins_with("Arm1") else 20)
		joint = cone
	joint.name = "Joint_" + bone_name.replace(".", "_")
	add_child(joint)
	var along: Vector3 = (entry.end - entry.start).normalized()
	var joint_basis := _axis_basis(along)
	if hinge:
		var upper: Vector3 = (parent.end - parent.start).normalized()
		var z := upper.cross(along).normalized()
		if z.length_squared() < .1:
			z = _axis_basis(along).x
		var x := along.cross(z).normalized()
		joint_basis = Basis(x, z.cross(x).normalized(), z)
	else:
		# ConeTwist's twist axis is X, aligned with the limb.
		joint_basis = Basis(joint_basis.y, joint_basis.z, joint_basis.x)
	joint.global_transform = Transform3D(joint_basis, entry.start)
	joint.node_a = joint.get_path_to(parent.body)
	joint.node_b = joint.get_path_to(entry.body)
	joint.exclude_nodes_from_collision = true
	joint.set_meta("child_body_name", entry.name)
	joint.set_meta("parent_body_name", parent.name)
	joints.append(joint)

func remove_severed_parts() -> void:
	if phase not in ["simulating", "settled"] or not is_instance_valid(actor.get("dismemberment")):
		return
	var removed: Array[String] = []
	for name_value: String in parts:
		if actor.dismemberment.is_bone_severed(name_value):
			removed.append(name_value)
	if removed.is_empty():
		return
	# Remove constraints first so a missing limb cannot pull on its old parent.
	for index in range(joints.size() - 1, -1, -1):
		var joint := joints[index]
		if str(joint.get_meta("child_body_name", "")) in removed or str(joint.get_meta("parent_body_name", "")) in removed:
			_disable_joint(joint)
			joints.remove_at(index)
	for index in range(pose_order.size() - 1, -1, -1):
		var entry: Dictionary = pose_order[index]
		if str(entry.name) in removed:
			_disable_body(entry.body)
			parts.erase(entry.name)
			pose_order.remove_at(index)
	quiet_time = 0.0
	ground_supported = false
	core_low = false
	settled_evidence.clear()
	# Removing a support from a settled body requires a new physical settling.
	if phase == "settled":
		phase = "simulating"
		for entry: Dictionary in pose_order:
			entry.body.freeze = false
			entry.body.sleeping = false
		set_physics_process(true)

func _disable_joint(joint: Joint3D) -> void:
	joint.node_a = NodePath()
	joint.node_b = NodePath()
	joint.queue_free()

func _disable_body(body: RigidBody3D) -> void:
	body.freeze = true
	body.collision_layer = 0
	body.collision_mask = 0
	body.queue_free()

func take_recovery_pose() -> Dictionary:
	if not temporary or phase != "settled" or actor.ai_state == DungeonEnemy.AIState.DEAD:
		return {}
	# Modifiers can run after actor physics. Synchronize before capturing so the
	# handoff includes this exact final physical frame, including independent IK roots.
	driver.call("apply_physical_pose")
	var bones: Array[Transform3D] = []
	for bone in rig.get_bone_count():
		bones.append(rig.global_transform * rig.get_bone_global_pose(bone))
	var result := {"bones": bones, "ground_point": ground_point, "evidence": settled_evidence.duplicate(true)}
	driver.active = false
	for joint: Joint3D in joints:
		_disable_joint(joint)
	for entry: Dictionary in pose_order:
		_disable_body(entry.body)
	joints.clear()
	pose_order.clear()
	parts.clear()
	initial_pose.clear()
	phase = "living"
	temporary = false
	set_physics_process(false)
	return result

func _settle() -> void:
	# Freeze the actual solved pose, not the original animation's end pose.
	driver.call("apply_physical_pose")
	settled_evidence = {"temporary": temporary, "ground_supported": ground_supported,
		"core_low": core_low, "ground_point": ground_point, "support_parts": support_parts.duplicate(),
		"support_normals": support_normals.duplicate(), "quiet_time": quiet_time,
		"mean_squared_speed": mean_squared_speed, "simulation_time": simulation_time}
	for entry: Dictionary in pose_order:
		var body: RigidBody3D = entry.body
		body.linear_velocity = Vector3.ZERO
		body.angular_velocity = Vector3.ZERO
		body.freeze = true
	phase = "settled"
	set_physics_process(false)

func snapshot() -> Dictionary:
	var positions := {}
	var max_speed := 0.0
	for entry: Dictionary in pose_order:
		positions[entry.name] = entry.body.global_position
		max_speed = maxf(max_speed, entry.body.linear_velocity.length())
	return {"phase": phase, "temporary": temporary, "reaction_time": reaction_time, "simulation_time": simulation_time,
		"execution_held": phase == "execution_hold", "execution_release_reason": execution_release_reason,
		"execution_release_pending": phase == "execution_hold" and not execution_release_reason.is_empty(),
		"bodies": parts.size(), "joints": joints.size(), "max_speed": max_speed, "positions": positions, "impact_velocity": impact_velocity,
		"ground_supported": ground_supported, "core_low": core_low, "ground_point": ground_point,
		"support_parts": support_parts.duplicate(), "support_normals": support_normals.duplicate(),
		"quiet_time": quiet_time, "mean_squared_speed": mean_squared_speed, "settled_evidence": settled_evidence.duplicate(true)}
