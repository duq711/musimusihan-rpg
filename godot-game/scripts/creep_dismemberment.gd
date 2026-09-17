extends Node3D
## Anatomical hits accumulate independently. Geometry is split offline; only the
## struck part is baked once at the current pose and released as a rigid body.
const MODEL_PATH := "res://assets/licensed/creep/creep_dismembered.glb"
const SEVERED_PART := preload("res://scripts/creep_severed_part.gd")
const RAGDOLL := preload("res://scripts/creep_ragdoll.gd")
const REGIONS := ["left_arm", "right_arm", "left_leg", "right_leg", "head"]
const DAMAGE_THRESHOLD := 35.0
const MIN_HITS := 2
const REGION_BONES := {
	"left_arm": ["Arm1.L", "Arm2.L", "Hand.L"],
	"right_arm": ["Arm1.R", "Arm2.R", "Hand.R"],
	"left_leg": ["Leg1.L", "Leg2.L", "Leg3.L", "Foot.L"],
	"right_leg": ["Leg1.R", "Leg2.R", "Leg3.R", "Foot.R"],
	"head": ["Neck", "Head"],
}
const AIM_BONES := {"left_arm": "Arm2.L", "right_arm": "Arm2.R", "left_leg": "Leg2.L", "right_leg": "Leg2.R", "head": "Head"}

var actor: Node3D
var rig: Skeleton3D
var enabled := false
var damage: Dictionary = {}
var hit_counts: Dictionary = {}
var severed: Array[String] = []
var meshes: Dictionary = {}
var body_caps: Dictionary = {}
var part_caps: Dictionary = {}
var detached: Array[RigidBody3D] = []
var base_move_speed := 2.2
var last_region := "torso"
var last_bake_ms := 0
var attachments: Array[Dictionary] = []
var last_cut_point := Vector3.INF
var last_cut_frame := -2

func configure(owner_actor: Node3D, skeleton: Skeleton3D) -> void:
	actor = owner_actor
	rig = skeleton
	base_move_speed = actor.move_speed
	for region: String in REGIONS:
		damage[region] = 0.0
		hit_counts[region] = 0
		meshes[region] = []
		body_caps[region] = []
		part_caps[region] = []
	_collect(actor.model_root)
	enabled = true
	for region: String in REGIONS:
		enabled = enabled and not meshes[region].is_empty() and not body_caps[region].is_empty() and not part_caps[region].is_empty()
	set_physics_process(false)

func create_attachment(point: Vector3) -> Node3D:
	# The projectile that completes the cut embeds in the newly released part.
	if Engine.get_physics_frames() - last_cut_frame <= 1 and point.distance_to(last_cut_point) < .05 and not detached.is_empty():
		return detached.back()
	var chosen: Dictionary = {}
	var nearest := INF
	for segment: Dictionary in _segments():
		var distance := point.distance_to(Geometry3D.get_closest_point_to_segment(point, segment.start, segment.end))
		if distance < nearest:
			nearest = distance
			chosen = segment
	if chosen.is_empty(): return actor
	var anchor := Node3D.new()
	anchor.name = "CreepHitAttachment"
	add_child(anchor)
	anchor.set_as_top_level(true)
	var bone := rig.find_bone(chosen.bone)
	anchor.global_transform = rig.global_transform * rig.get_bone_global_pose(bone)
	attachments.append({"node": anchor, "bone": bone, "region": chosen.region})
	set_physics_process(true)
	return anchor

func _physics_process(_delta: float) -> void:
	for attachment: Dictionary in attachments:
		if is_instance_valid(attachment.node):
			attachment.node.global_transform = rig.global_transform * rig.get_bone_global_pose(attachment.bone)

func _collect(node: Node) -> void:
	if node is MeshInstance3D:
		for region: String in REGIONS:
			if str(node.name).begins_with("CreepPart_" + region):
				meshes[region].append(node)
			elif str(node.name).begins_with("CreepCap_body_" + region):
				body_caps[region].append(node)
				node.hide()
			elif str(node.name).begins_with("CreepCap_part_" + region):
				part_caps[region].append(node)
				node.hide()
	for child in node.get_children():
		_collect(child)

func region_for_bone(bone_name: String) -> String:
	for region: String in REGIONS:
		if bone_name in REGION_BONES[region]: return region
	return "torso"

func is_bone_severed(bone_name: String) -> bool:
	return region_for_bone(bone_name) in severed

func _bone_position(bone_name: String) -> Vector3:
	return (rig.global_transform * rig.get_bone_global_pose(rig.find_bone(bone_name))).origin

func _segments() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for spec: Array in RAGDOLL.PARTS:
		var region := region_for_bone(spec[0])
		if region in severed: continue
		var start := _bone_position(spec[0])
		var bone_world := rig.global_transform * rig.get_bone_global_pose(rig.find_bone(spec[0]))
		var end: Vector3 = _bone_position(spec[1]) if not str(spec[1]).is_empty() else start + bone_world.basis.y.normalized() * float(spec[5])
		if not str(spec[1]).is_empty(): end += start.direction_to(end) * float(spec[5])
		result.append({"start": start, "end": end, "radius": float(spec[3]), "region": region, "bone": spec[0]})
	return result

func hit_point_for_region(region: String) -> Vector3:
	for segment: Dictionary in _segments():
		if segment.bone == AIM_BONES.get(region, "Chest"):
			return (segment.start + segment.end) * .5
	return _bone_position("Chest")

func region_at_point(point: Vector3) -> String:
	var best := INF
	var region := ""
	for segment: Dictionary in _segments():
		var closest := Geometry3D.get_closest_point_to_segment(point, segment.start, segment.end)
		var distance := point.distance_to(closest) / float(segment.radius)
		if distance <= 1.55 and distance < best:
			best = distance
			region = segment.region
	return region

func query_hit(from: Vector3, to: Vector3, radius: float = 0.0) -> Dictionary:
	if actor.health <= 0.0: return {}
	var nearest := INF
	var region := ""
	var segments := _segments()
	for segment: Dictionary in segments:
		var t := _capsule_fraction(from, to, segment.start, segment.end, float(segment.radius) + maxf(0, radius))
		if t < nearest:
			nearest = t
			region = segment.region
	if nearest == INF: return {}
	var contact := from.lerp(to, nearest)
	# The centre of a swept sphere is not the contact on the anatomy surface.
	# Project onto the selected capsule so receive_located_hit can classify it.
	var best_surface := INF
	var anatomical_contact := contact
	for segment: Dictionary in segments:
		if segment.region != region: continue
		var axis_point := Geometry3D.get_closest_point_to_segment(contact, segment.start, segment.end)
		var distance := absf(contact.distance_to(axis_point) - float(segment.radius))
		if distance < best_surface:
			best_surface = distance
			anatomical_contact = axis_point + axis_point.direction_to(contact) * float(segment.radius)
	return {"position": anatomical_contact, "region": region, "fraction": nearest}

static func _sphere_fraction(from: Vector3, direction: Vector3, centre: Vector3, radius: float) -> float:
	var offset := from - centre
	var a := direction.length_squared()
	var c := offset.length_squared() - radius * radius
	if c <= 0.0: return 0.0
	if a < .0000001: return INF
	var b := offset.dot(direction)
	var discriminant := b * b - a * c
	if discriminant < 0.0: return INF
	var t := (-b - sqrt(discriminant)) / a
	return t if t >= 0.0 and t <= 1.0 else INF

static func _capsule_fraction(from: Vector3, to: Vector3, start: Vector3, end: Vector3, radius: float) -> float:
	var direction := to - from
	var axis := end - start
	var length_squared := axis.length_squared()
	var nearest := minf(_sphere_fraction(from, direction, start, radius), _sphere_fraction(from, direction, end, radius))
	if length_squared < .0000001: return nearest
	if from.distance_to(Geometry3D.get_closest_point_to_segment(from, start, end)) <= radius: return 0.0
	var offset := from - start
	var axis_dir := axis.dot(direction)
	var axis_offset := axis.dot(offset)
	var a := length_squared * direction.length_squared() - axis_dir * axis_dir
	var b := length_squared * direction.dot(offset) - axis_offset * axis_dir
	var c := length_squared * offset.length_squared() - axis_offset * axis_offset - radius * radius * length_squared
	var h := b * b - a * c
	if absf(a) > .0000001 and h >= 0.0:
		var t := (-b - sqrt(h)) / a
		var y := axis_offset + t * axis_dir
		if t >= 0.0 and t <= 1.0 and y >= 0.0 and y <= length_squared:
			nearest = minf(nearest, t)
	return nearest

func register_hit(amount: float, point: Vector3, attacker_position: Vector3) -> String:
	last_region = region_at_point(point)
	if not enabled or amount <= 0.0 or last_region not in REGIONS or last_region in severed:
		return ""
	damage[last_region] += amount
	hit_counts[last_region] += 1
	if damage[last_region] >= DAMAGE_THRESHOLD and hit_counts[last_region] >= MIN_HITS:
		if _sever(last_region, attacker_position):
			last_cut_point = point
			last_cut_frame = Engine.get_physics_frames()
			return last_region
	return ""

func _sever(region: String, attacker_position: Vector3) -> bool:
	var start_ms := Time.get_ticks_msec()
	var pieces: Array = meshes[region] + part_caps[region]
	var body := SEVERED_PART.new()
	body.region = region
	body.name = "Severed_" + region
	body.mass = 5.0 if region == "head" else (7.0 if region.ends_with("leg") else 4.0)
	body.freeze = true
	body.collision_layer = 32
	body.collision_mask = 2 | 32
	body.continuous_cd = true
	body.linear_damp = .5
	body.angular_damp = .9
	body.contact_monitor = true
	body.max_contacts_reported = 6
	body.physics_material_override = PhysicsMaterial.new()
	body.physics_material_override.friction = .85
	body.physics_material_override.bounce = .02
	add_child(body)
	body.set_as_top_level(true)
	body.global_transform = Transform3D(Basis.IDENTITY, hit_point_for_region(region))
	var points := PackedVector3Array()
	for source: MeshInstance3D in pieces:
		var baked := _bake_world_mesh(source, body.global_position)
		var display := MeshInstance3D.new()
		display.mesh = baked
		display.name = source.name
		body.add_child(display)
		for surface in baked.get_surface_count():
			points.append_array(baked.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX])
	if points.size() < 4:
		body.queue_free()
		return false
	var collision := CollisionShape3D.new()
	var convex := ConvexPolygonShape3D.new()
	convex.points = points
	collision.shape = convex
	body.add_child(collision)
	for mesh: MeshInstance3D in meshes[region]: mesh.hide()
	for cap: MeshInstance3D in body_caps[region]: cap.show()
	severed.append(region)
	detached.append(body)
	for index in range(attachments.size() - 1, -1, -1):
		var attachment := attachments[index]
		if attachment.region == region:
			var anchor: Node3D = attachment.node
			if is_instance_valid(anchor):
				anchor.global_transform = rig.global_transform * rig.get_bone_global_pose(attachment.bone)
				var world_pose := anchor.global_transform
				anchor.reparent(body)
				anchor.set_as_top_level(false)
				anchor.global_transform = world_pose
			attachments.remove_at(index)
	var impulse_direction := attacker_position.direction_to(body.global_position)
	impulse_direction.y = .35
	body.freeze = false
	body.linear_velocity = actor.velocity.limit_length(2.0) + impulse_direction.normalized() * 1.1
	body.angular_velocity = Vector3(1.4, .6, -.8)
	last_bake_ms = Time.get_ticks_msec() - start_ms
	_update_mobility()
	return true

func _bake_world_mesh(source: MeshInstance3D, origin: Vector3) -> ArrayMesh:
	# CPU skinning also works in headless physics tests, without GPU readback.
	# Keep the imported eight weights and each surface's original PBR material.
	var skin := source.skin
	var transforms: Array[Transform3D] = []
	for bind in skin.get_bind_count():
		var bone := rig.find_bone(skin.get_bind_name(bind))
		if bone < 0: bone = skin.get_bind_bone(bind)
		transforms.append(rig.global_transform * rig.get_bone_global_pose(bone) * skin.get_bind_pose(bind))
	var result := ArrayMesh.new()
	for surface in source.mesh.get_surface_count():
		var arrays := source.mesh.surface_get_arrays(surface).duplicate(true)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var tangents: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT] if arrays[Mesh.ARRAY_TANGENT] != null else PackedFloat32Array()
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var stride := weights.size() / vertices.size()
		for vertex in vertices.size():
			var point := Vector3.ZERO
			var normal := Vector3.ZERO
			var tangent := Vector3.ZERO
			for slot in stride:
				var weight := weights[vertex * stride + slot]
				if weight <= .000001: continue
				var transform := transforms[bones[vertex * stride + slot]]
				point += (transform * vertices[vertex]) * weight
				normal += (transform.basis * normals[vertex]) * weight
				if not tangents.is_empty():
					tangent += (transform.basis * Vector3(tangents[vertex * 4], tangents[vertex * 4 + 1], tangents[vertex * 4 + 2])) * weight
			vertices[vertex] = point - origin
			normals[vertex] = normal.normalized()
			if not tangents.is_empty():
				tangent = tangent.normalized()
				tangents[vertex * 4] = tangent.x
				tangents[vertex * 4 + 1] = tangent.y
				tangents[vertex * 4 + 2] = tangent.z
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_NORMAL] = normals
		if not tangents.is_empty(): arrays[Mesh.ARRAY_TANGENT] = tangents
		arrays[Mesh.ARRAY_BONES] = null
		arrays[Mesh.ARRAY_WEIGHTS] = null
		result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		result.surface_set_material(surface, source.get_active_material(surface))
	return result

func missing_legs() -> int:
	return int("left_leg" in severed) + int("right_leg" in severed)

func _update_mobility() -> void:
	var legs := missing_legs()
	actor.move_speed = base_move_speed * [1.0, .50, .18][legs]
	actor.attack_range = 1.15 if legs > 0 else 1.50
	# Keep the bottom of the living capsule at the floor after lowering the body.
	var height: float = 1.80 if legs == 0 else .86
	actor.collision_shape.shape.height = height
	actor.collision_shape.position.y = (height - 1.80) * .5

func apply_living_pose(delta: float) -> void:
	if missing_legs() > 0 and is_instance_valid(actor.crawl):
		actor.crawl.apply(delta)

func snapshot() -> Dictionary:
	var positions := {}
	for body in detached:
		if is_instance_valid(body): positions[body.region] = body.global_position
	return {"enabled": enabled, "damage": damage.duplicate(), "hit_counts": hit_counts.duplicate(), "severed": severed.duplicate(), "detached_bodies": detached.size(), "positions": positions, "last_region": last_region, "last_bake_ms": last_bake_ms, "move_speed": actor.move_speed}
