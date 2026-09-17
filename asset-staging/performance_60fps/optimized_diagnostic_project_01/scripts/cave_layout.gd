extends RefCounted
## Godot and the Blender build read the same hand-traced 18-chamber mine plan.
## X points east and Z points south. Each world unit is one metre.

const WIDTH := 131.0
const DEPTH := 139.0
const SEED := 139131
const DATA_PATH := "res://assets/3d/abandoned_mine/layout.json"

static var _source: Dictionary = {}

static func source_data() -> Dictionary:
	if _source.is_empty():
		var decoded: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
		assert(decoded is Dictionary, "The Blender mine plan must be present and valid JSON")
		_source = decoded
	return _source.duplicate(true)

static func rooms() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for value: Dictionary in source_data().get("rooms", []):
		var room := value.duplicate(true)
		room.center = _point2(value.center)
		room.polygon = _polygon(value.polygon)
		var box := Rect2(room.polygon[0], Vector2.ZERO)
		for point: Vector2 in room.polygon:
			box = box.expand(point)
		# Compatibility for camera framing only; room membership is polygonal.
		room.radii = box.size * 0.5
		result.append(room)
	return result

static func corridors() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for value: Dictionary in source_data().get("corridors", []):
		var corridor := value.duplicate(true)
		corridor.points = _polygon(value.points)
		result.append(corridor)
	return result

static func corridor_points(link: Dictionary) -> Array[Vector2]:
	var result: Array[Vector2] = []
	for point: Variant in link.get("points", []):
		result.append(point if point is Vector2 else _point2(point))
	return result

static func pools() -> Array[Dictionary]:
	return _polygon_entries("pools")

static func islands() -> Array[Dictionary]:
	return _polygon_entries("islands")

static func landmarks() -> Array[Dictionary]:
	return _position_entries(source_data().get("landmarks", []))

static func bridges() -> Array[Dictionary]:
	return _position_entries(source_data().get("bridges", []))

static func gameplay(kind: String) -> Array[Dictionary]:
	return _position_entries(source_data().get("gameplay", {}).get(kind, []))

static func room_position(id: String) -> Vector3:
	for room: Dictionary in rooms():
		if room.id == id:
			return Vector3(room.center.x, float(room.get("floor_y", 0)), room.center.y)
	push_error("Unknown authored mine room: " + id)
	return Vector3.ZERO

static func room_id_at(point: Vector2) -> String:
	for room: Dictionary in rooms():
		if Geometry2D.is_point_in_polygon(point, room.polygon):
			return str(room.id)
	return ""

static func spawn_position() -> Vector3:
	return _point3(source_data().spawn)

static func extraction_position() -> Vector3:
	return _point3(source_data().extraction)

static func bounds() -> Rect2:
	return Rect2(-WIDTH * 0.5, -DEPTH * 0.5, WIDTH, DEPTH)

static func _polygon_entries(key: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for value: Dictionary in source_data().get(key, []):
		var entry := value.duplicate(true)
		entry.polygon = _polygon(value.polygon)
		result.append(entry)
	return result

static func _position_entries(values: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for value: Dictionary in values:
		var entry := value.duplicate(true)
		entry.position = _point3(value.position)
		result.append(entry)
	return result

static func _polygon(values: Array) -> PackedVector2Array:
	var result := PackedVector2Array()
	for value: Array in values:
		result.append(_point2(value))
	return result

static func _point2(value: Array) -> Vector2:
	return Vector2(float(value[0]), float(value[1]))

static func _point3(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))
