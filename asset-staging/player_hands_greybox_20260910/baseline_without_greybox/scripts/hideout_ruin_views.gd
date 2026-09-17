extends RefCounted
## Shared room views for the playable test-room inspection and unretouched
## renderer evidence. Every image is one room; coordinates are camera eyes.

const IMAGE_SIZE := Vector2i(1280, 720)
const SHOTS: Array[Dictionary] = [
	{"id": "central", "region_id": "central", "title": "중앙 저수 홀", "position": Vector3(0.0, 1.7, 8.4), "target": Vector3(0.0, 1.65, -4.8), "fov": 76.0},
	{"id": "entrance", "region_id": "entrance", "title": "예배당 진입 계단", "position": Vector3(0.0, 1.7, 12.1), "target": Vector3(0.0, 2.0, 23.5), "fov": 76.0},
	{"id": "sleep", "region_id": "sleep", "title": "관리인의 침실", "position": Vector3(-8.95, 1.7, 3.8), "target": Vector3(-12.5, 1.35, 6.2), "fov": 76.0},
	{"id": "storage", "region_id": "storage", "title": "빈 저장고", "position": Vector3(9.1, 1.7, 3.3), "target": Vector3(13.0, 1.3, 6.1), "fov": 76.0},
	{"id": "workshop", "region_id": "workshop", "title": "무너진 공방", "position": Vector3(8.8, 1.7, -4.85), "target": Vector3(12.8, 1.35, -4.85), "fov": 76.0},
	{"id": "flooded_store", "region_id": "flooded_store", "title": "침수된 저장고", "position": Vector3(-8.9, 1.7, -3.15), "target": Vector3(-12.5, 1.4, -5.7), "fov": 76.0},
	{"id": "ossuary", "region_id": "ossuary", "title": "봉인된 납골실", "position": Vector3(0.0, 1.7, -11.65), "target": Vector3(0.0, 1.6, -18.7), "fov": 76.0},
	{"id": "drain", "region_id": "drain", "title": "붕괴된 배수로", "position": Vector3(17.25, 1.7, -5.0), "target": Vector3(23.6, 1.5, -5.0), "fov": 76.0},
]


static func ordered_ids() -> Array[String]:
	var result: Array[String] = []
	for shot in SHOTS:
		result.append(str(shot.id))
	return result


static func get_shot(room_id: String) -> Dictionary:
	for shot in SHOTS:
		if str(shot.id) == room_id:
			return shot.duplicate(true)
	return {}


static func selected_shots(value: String) -> Array[Dictionary]:
	var requested: Array[String] = []
	for token in value.strip_edges().split(",", false):
		var room_id := token.strip_edges()
		if room_id not in ordered_ids():
			return []
		requested.append(room_id)
	var result: Array[Dictionary] = []
	for shot in SHOTS:
		if requested.is_empty() or str(shot.id) in requested:
			result.append(shot.duplicate(true))
	return result
