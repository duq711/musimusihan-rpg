extends RefCounted
## Preserve nearby lamp illumination while retiring distant shadow work.
const FULL_SHADOW_DISTANCE := 10.0


static func configure(light: OmniLight3D) -> void:
	# The existing light fade, range and radiance remain authoritative. Only
	# shadow fade begins earlier; full local wall occlusion is retained.
	light.distance_fade_shadow = FULL_SHADOW_DISTANCE


static func needs_flicker_update(light: OmniLight3D, camera: Camera3D) -> bool:
	if camera == null or not light.distance_fade_enabled:
		return true
	var invisible_after := light.distance_fade_begin + light.distance_fade_length
	return camera.global_position.distance_squared_to(light.global_position) <= invisible_after * invisible_after


static func flicker_energy(base_energy: float, clock: float, index: int) -> float:
	return base_energy * (0.98 + sin(clock * 6.1 + index * 1.7) * 0.018 + sin(clock * 9.3 + index) * 0.01)
