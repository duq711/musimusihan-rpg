extends RefCounted
## Shared geometry checks for the preview, commit and fixed deployed campsite.

const MAX_REACH := 5.0
const WORLD_MASK := 2 | 4
const FLOOR_MASK := 2
const MAX_FLOOR_STEP := 0.10
const MIN_FLOOR_NORMAL := 0.85
const ROOT_HEIGHT := 0.9
const SEAT_OFFSET := Vector3(0.0, 0.0, 1.1)
const TENT_OFFSET := Vector3(1.05, 0.0, -0.35)


static func aim(player: DungeonPlayer, game: Node, exclude: Array[RID] = []) -> Dictionary:
	if not is_instance_valid(player.camera):
		return _result(false, "no_ground", player.global_position, player.global_rotation.y)
	var origin := player.camera.global_position
	var target := origin - player.camera.global_basis.z * MAX_REACH
	var yaw := player.global_rotation.y
	var query := PhysicsRayQueryParameters3D.create(origin, target, WORLD_MASK, _exclude_player(player, exclude))
	var hit := player.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return _result(false, "no_ground", target, yaw)
	var center: Vector3 = hit.position
	if (hit.normal as Vector3).y < MIN_FLOOR_NORMAL:
		return _result(false, "uneven_ground", center, yaw)
	return validate(player, game, center, yaw, exclude)


static func validate(player: DungeonPlayer, game: Node, center: Vector3, yaw: float, exclude: Array[RID] = []) -> Dictionary:
	var exclusions := _exclude_player(player, exclude)
	var basis := Basis(Vector3.UP, yaw)
	for offset: Vector3 in floor_samples():
		var point := center + basis * offset
		var hit := _floor(player, point, exclusions)
		if hit.is_empty() or (hit.normal as Vector3).y < MIN_FLOOR_NORMAL or absf((hit.position as Vector3).y - center.y) > MAX_FLOOR_STEP:
			return _result(false, "uneven_ground", center, yaw)
		if _wet(game, hit.position):
			return _result(false, "wet_ground", center, yaw)
	# The box includes poles/roof, not only the fire's old small sphere.
	for volume: Dictionary in [
		{"at": Vector3(0, 0.51, 0), "size": Vector3(0.94, 0.92, 0.94)},
		{"at": TENT_OFFSET + Vector3(0, 0.57, 0), "size": Vector3(1.18, 1.06, 1.78)},
		{"at": SEAT_OFFSET + Vector3(0, 0.95, 0), "size": Vector3(0.72, 1.78, 0.72)}
	]:
		var shape := BoxShape3D.new()
		shape.size = volume.size
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = shape
		query.transform = Transform3D(basis, center + basis * (volume.at as Vector3))
		query.collision_mask = WORLD_MASK
		query.exclude = exclusions
		query.collide_with_areas = false
		if not player.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty():
			return _result(false, "blocked_space", center, yaw)
	return _result(true, "", center, yaw)


static func floor_samples() -> Array[Vector3]:
	var result: Array[Vector3] = []
	for x in [-0.43, 0.0, 0.43]:
		for z in [-0.43, 0.0, 0.43]: result.append(Vector3(x, 0, z))
	for x in [0.48, 1.05, 1.62]:
		for z in [-1.22, -0.78, -0.35, 0.09, 0.52]: result.append(Vector3(x, 0, z))
	for x in [-0.34, 0.0, 0.34]:
		for z in [0.76, 1.1, 1.44]: result.append(Vector3(x, 0, z))
	return result


static func seat_position(center: Vector3, yaw: float) -> Vector3:
	return center + Basis(Vector3.UP, yaw) * SEAT_OFFSET + Vector3.UP * ROOT_HEIGHT


static func walking_path_clear(player: DungeonPlayer, game: Node, from: Vector3, to: Vector3, exclude: Array[RID] = []) -> bool:
	var exclusions := _exclude_player(player, exclude)
	var steps := maxi(1, ceili(from.distance_to(to) / 0.22))
	var previous_height := from.y - ROOT_HEIGHT
	for step in range(steps + 1):
		var point := from.lerp(to, float(step) / float(steps)) - Vector3.UP * ROOT_HEIGHT
		var hit := _floor(player, point, exclusions)
		if hit.is_empty() or (hit.normal as Vector3).y < MIN_FLOOR_NORMAL:
			return false
		var floor_point: Vector3 = hit.position
		if absf(floor_point.y - previous_height) > 0.18 or _wet(game, floor_point): return false
		previous_height = floor_point.y
		var capsule := CapsuleShape3D.new()
		capsule.radius = 0.31
		capsule.height = 1.72
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = capsule
		query.transform = Transform3D(Basis.IDENTITY, floor_point + Vector3.UP * 0.91)
		query.collision_mask = WORLD_MASK
		query.exclude = exclusions
		query.collide_with_areas = false
		if not player.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty(): return false
	return true


static func _floor(player: DungeonPlayer, point: Vector3, exclude: Array[RID]) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(point + Vector3.UP * 0.45, point + Vector3.DOWN * 0.55, FLOOR_MASK, exclude)
	return player.get_world_3d().direct_space_state.intersect_ray(query)


static func _wet(game: Node, point: Vector3) -> bool:
	var water: Node = game.get_node_or_null("CaveGeometry/CaveWater") if is_instance_valid(game) else null
	if not is_instance_valid(water) or not water.has_method("sample_surface"): return false
	var sample: Dictionary = water.sample_surface(point)
	return not sample.is_empty() and point.y <= float(sample.height) + 0.035


static func _exclude_player(player: DungeonPlayer, extra: Array[RID]) -> Array[RID]:
	var result: Array[RID] = extra.duplicate()
	if not result.has(player.get_rid()): result.append(player.get_rid())
	return result


static func _result(accepted: bool, reason: String, position: Vector3, yaw: float) -> Dictionary:
	return {"accepted": accepted, "reason": reason, "position": position, "yaw": yaw}
