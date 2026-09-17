extends RefCounted

# Anatomical targets supply contacts from their current posed body regions.
# Their broad navigation capsule must not absorb attacks through a missing limb.
static func collect(tree: SceneTree, from: Vector3, to: Vector3, radius: float = 0.0, excluded: Array[RID] = []) -> Dictionary:
	var result := {"hit": {}, "excluded": excluded.duplicate(), "bodies": []}
	for candidate in tree.get_nodes_in_group("enemy"):
		if not is_instance_valid(candidate) or not candidate is CollisionObject3D or not candidate.has_method("query_located_hit"):
			continue
		var body := candidate as CollisionObject3D
		if excluded.has(body.get_rid()) or body.collision_layer & 4 == 0:
			continue
		result.excluded.append(body.get_rid())
		result.bodies.append(body)
		var contact: Dictionary = candidate.call("query_located_hit", from, to, radius)
		if contact.is_empty() or not contact.get("position") is Vector3:
			continue
		var point: Vector3 = contact.position
		if not point.is_finite():
			continue
		contact = contact.duplicate()
		contact.collider = candidate
		result.hit = nearer(result.hit, contact, from, to)
	return result


static func nearer(first: Dictionary, second: Dictionary, from: Vector3, to: Vector3) -> Dictionary:
	if first.is_empty():
		return second
	if second.is_empty():
		return first
	# The first argument wins equal-depth contacts, so callers pass world
	# collisions first and cannot shoot a region through a flush wall.
	# Compare time of contact, not surface-point depth: an off-centre sphere
	# contact and a flat wall have different offsets from the moving centre.
	return second if _fraction(second, from, to) < _fraction(first, from, to) - 0.0001 else first


static func _fraction(hit: Dictionary, from: Vector3, to: Vector3) -> float:
	if hit.has("fraction"):
		return float(hit.fraction)
	var motion := to - from
	return (hit.position - from).dot(motion) / motion.length_squared() if motion.length_squared() > 0.000001 else 0.0
