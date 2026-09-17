extends RefCounted
## Shared assertions for executable entrance and waterside TestRoom visits.
const PREVIEW := preload("res://tests/art_direction_preview.gd")


static func inspect(cave: Node3D) -> Array[String]:
	var failures: Array[String] = []
	var geometry: Node3D = cave.cave_geometry
	if not await PREVIEW.await_geometry_ready(geometry):
		failures.append("playable art direction must finish attaching its fixtures before testing")
	var player: DungeonPlayer = cave.player
	if player.game != cave or player.inventory_model != cave.inventory:
		failures.append("art direction trial must retain the actual gameplay and inventory bindings")
	var environment := cave.find_child("WorldEnvironment", true, false) as WorldEnvironment
	if environment == null or environment.environment.ambient_light_color.b <= environment.environment.ambient_light_color.r:
		failures.append("playable art direction must use its cool production cave atmosphere")
	var roles: Dictionary = {}
	for visual in geometry.blender_mine.find_children("Terrain_*", "MeshInstance3D", true, false):
		for surface in range(visual.mesh.get_surface_count()):
			var material := visual.get_active_material(surface) as ShaderMaterial
			if material != null:
				roles[bool(material.get_shader_parameter("ground_surface"))] = true
	if not roles.has(true) or not roles.has(false):
		failures.append("playable trial must use distinct actual earth and rock shading")
	for property in ["art_lighting", "art_details"]:
		var system: Node = geometry.get(property)
		if system == null:
			failures.append("playable trial must include the production " + property)
		elif not bool(system.call("get_state_snapshot").get("ready", false)):
			failures.append("playable trial must finish building " + property)
	var original_torch: bool = player.torch_enabled
	var base := float(player.torch.get_meta("base_energy", 0.0))
	if base <= 0.0 or player.torch.light_color.r <= player.torch.light_color.b:
		failures.append("playable trial must apply the warm production animated torch profile")
	player.set_torch_enabled(false)
	player._update_torch(0.1)
	if player.torch.visible or player.torch_fill.visible:
		failures.append("torch comparison must disable the actual world light")
	player.set_torch_enabled(true)
	player._update_torch(0.25)
	if not player.torch.visible or absf(player.torch.light_energy - base) >= base * 0.15:
		failures.append("torch comparison must restore the current cave profile through normal flicker")
	player.set_torch_enabled(original_torch)
	return failures
