extends RefCounted
## Authoritative metre-based footprint and connected chamber graph.
## X is east/west; Z is north/south. One Godot unit is one metre.

const WIDTH := 131.0
const DEPTH := 139.0
const SEED := 139131

static func rooms() -> Array[Dictionary]:
	return [
		{"id": "entrance", "title": "꺼져 가는 갱도", "center": Vector2(0, 57), "radii": Vector2(12, 11.5), "height": 6.5},
		{"id": "flooded", "title": "검은 물 웅덩이", "center": Vector2(-32, 32), "radii": Vector2(18, 14), "height": 8.5},
		{"id": "mine", "title": "버려진 채굴장", "center": Vector2(35, 33), "radii": Vector2(17, 14), "height": 7.0},
		{"id": "crossroads", "title": "속삭임의 갈림길", "center": Vector2(0, 5), "radii": Vector2(16, 16), "height": 9.0},
		{"id": "crypt", "title": "잠긴 납골굴", "center": Vector2(-41, -14), "radii": Vector2(17.5, 13), "height": 6.5},
		{"id": "chapel", "title": "매몰된 예배당", "center": Vector2(34, -18), "radii": Vector2(17, 17), "height": 10.0},
		{"id": "reliquary", "title": "심층 성물고", "center": Vector2(0, -51), "radii": Vector2(19, 15), "height": 9.0},
		{"id": "west_shrine", "title": "잊힌 순교자의 샘", "center": Vector2(-48, -51), "radii": Vector2(14.5, 15), "height": 7.0},
		{"id": "east_cache", "title": "밀수꾼의 무덤", "center": Vector2(48, -52), "radii": Vector2(14, 15), "height": 7.0},
	]

static func corridors() -> Array[Dictionary]:
	return [
		_link("entrance", "flooded", 6.5, Vector2(-15, 47)),
		_link("entrance", "mine", 6.5, Vector2(20, 50)),
		_link("entrance", "crossroads", 7.0, Vector2(5, 32)),
		_link("flooded", "crossroads", 7.0, Vector2(-21, 9)),
		_link("mine", "crossroads", 7.0, Vector2(25, 7)),
		_link("flooded", "crypt", 6.0, Vector2(-45, 10)),
		_link("mine", "chapel", 6.0, Vector2(45, 8)),
		_link("crossroads", "crypt", 7.0, Vector2(-21, -11)),
		_link("crossroads", "chapel", 7.0, Vector2(17, -14)),
		_link("crossroads", "reliquary", 7.0, Vector2(-6, -27)),
		_link("crypt", "west_shrine", 6.0, Vector2(-49, -32)),
		_link("chapel", "east_cache", 6.0, Vector2(46, -34)),
		_link("west_shrine", "reliquary", 6.5, Vector2(-26, -55)),
		_link("east_cache", "reliquary", 6.5, Vector2(25, -53)),
	]

static func _link(from: String, to: String, width: float, bend: Vector2) -> Dictionary:
	return {"from": from, "to": to, "width": width, "bend": bend}

static func room_position(id: String) -> Vector3:
	for room in rooms():
		if room.id == id:
			return Vector3(room.center.x, 0, room.center.y)
	return Vector3.ZERO

static func spawn_position() -> Vector3:
	return Vector3(0, 1.0, 61)

static func extraction_position() -> Vector3:
	return Vector3(0, 0, -60)

static func bounds() -> Rect2:
	return Rect2(-WIDTH * 0.5, -DEPTH * 0.5, WIDTH, DEPTH)

static func corridor_points(link: Dictionary) -> Array[Vector2]:
	var a := room_position(link.from)
	var b := room_position(link.to)
	return [Vector2(a.x, a.z), link.bend, Vector2(b.x, b.z)]
