extends RefCounted
## Retain the designed 720p detail budget when a Retina window grows; UI stays native.

const PIXEL_BUDGET := 1280.0 * 720.0
const MIN_SCALE := 0.5


static func scale_for(size: Vector2i) -> float:
	var area := float(maxi(size.x, 1)) * float(maxi(size.y, 1))
	return clampf(sqrt(PIXEL_BUDGET / area), MIN_SCALE, 1.0)


static func equipment_size_for(size: Vector2i) -> Vector2i:
	var scale := scale_for(size)
	return Vector2i(maxi(2, roundi(size.x * scale)), maxi(2, roundi(size.y * scale)))
