extends RefCounted
class_name CampVisuals

const WOOD: Texture2D = preload("res://assets/ai/materials/ancient_oak.png")
const STONE: Texture2D = preload("res://assets/ai/materials/wet_flagstone.png")
const FLAME: Texture2D = preload("res://assets/ai/vfx/torch_flame.png")


static func create_camp() -> Node3D:
	var camp := Node3D.new()
	camp.name = "CampVisual"
	var stone_material := _material(Color(0.33, 0.32, 0.29), STONE)
	var wood_material := _material(Color(0.28, 0.14, 0.06), WOOD)
	var cloth_material := _material(Color(0.27, 0.21, 0.13))
	for index in range(9):
		var stone := MeshInstance3D.new()
		stone.name = "FireRingStone%d" % index
		var sphere := SphereMesh.new()
		sphere.radius = 0.095
		sphere.height = 0.15
		sphere.radial_segments = 7
		sphere.rings = 4
		stone.mesh = sphere
		stone.material_override = stone_material
		var angle := index * TAU / 9.0
		stone.position = Vector3(cos(angle) * 0.33, 0.06, sin(angle) * 0.33)
		stone.rotation.y = angle
		stone.scale = Vector3(1.15, 0.8, 0.9)
		camp.add_child(stone)
	for index in range(4):
		var log := MeshInstance3D.new()
		log.name = "Firewood%d" % index
		var cylinder := CylinderMesh.new()
		cylinder.top_radius = 0.045
		cylinder.bottom_radius = 0.055
		cylinder.height = 0.48
		cylinder.radial_segments = 7
		log.mesh = cylinder
		log.material_override = wood_material
		log.position = Vector3(0.0, 0.075 + index * 0.016, 0.0)
		log.rotation = Vector3(PI / 2.0, index * PI / 3.0, 0.1)
		camp.add_child(log)
	var bed := MeshInstance3D.new()
	bed.name = "Bedroll"
	var mattress := BoxMesh.new()
	mattress.size = Vector3(0.34, 0.07, 0.82)
	bed.mesh = mattress
	bed.material_override = cloth_material
	bed.position = Vector3(0.66, 0.065, 0.1)
	bed.rotation.y = 0.12
	camp.add_child(bed)
	var pillow := MeshInstance3D.new()
	pillow.name = "RolledBlanket"
	var roll := CylinderMesh.new()
	roll.top_radius = 0.075
	roll.bottom_radius = 0.075
	roll.height = 0.34
	roll.radial_segments = 10
	pillow.mesh = roll
	pillow.material_override = cloth_material
	pillow.position = Vector3(0.69, 0.12, -0.23)
	pillow.rotation.z = PI / 2.0
	camp.add_child(pillow)
	var flame := Sprite3D.new()
	flame.name = "Flame"
	flame.texture = FLAME
	flame.pixel_size = 0.00075
	flame.position.y = 0.35
	flame.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	flame.alpha_cut = SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS
	flame.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	flame.double_sided = true
	flame.shaded = false
	camp.add_child(flame)
	var light := OmniLight3D.new()
	light.name = "CampfireLight"
	light.position = Vector3(0.0, 0.45, 0.0)
	light.light_color = Color(1.0, 0.52, 0.19)
	light.light_energy = 3.1
	light.omni_range = 6.0
	light.shadow_enabled = true
	camp.add_child(light)
	_create_cooking_tools(camp)
	return camp


static func animate(camp: Node3D, elapsed: float, warmth: int) -> void:
	if not is_instance_valid(camp):
		return
	var strength := 0.35 + 0.65 * clampf(float(warmth) / 3.0, 0.0, 1.0)
	var pulse := 1.0 + sin(elapsed * 13.0) * 0.06 + sin(elapsed * 23.0) * 0.025
	var flame := camp.get_node("Flame") as Node3D
	flame.scale = Vector3(1.0 / pulse, pulse, 1.0) * strength
	var light := camp.get_node("CampfireLight") as OmniLight3D
	light.light_energy = 3.1 * strength * pulse


static func set_cooking(camp: Node3D, recipe_id: String, progress: float, active: bool) -> void:
	if not is_instance_valid(camp):
		return
	var tools := camp.get_node_or_null("CookingTools") as Node3D
	if tools == null:
		tools = _create_cooking_tools(camp)
	var recipe := recipe_id.trim_prefix("cook:")
	var valid_recipe := recipe in ["roast_meat", "mushroom_soup", "trail_stew"]
	tools.visible = active and valid_recipe
	tools.set_meta("recipe_id", recipe if tools.visible else "")
	var amount := clampf(progress, 0.0, 1.0) if is_finite(progress) else 0.0
	tools.set_meta("progress", amount if tools.visible else 0.0)
	var spit := tools.get_node("RoastingSpit") as Node3D
	var pot := tools.get_node("SoupPot") as Node3D
	spit.visible = tools.visible and recipe == "roast_meat"
	pot.visible = tools.visible and recipe != "roast_meat"
	if not tools.visible:
		return
	# Progress comes only from the actual camp activity. Repeated snapshots,
	# pause, cancellation and completion cannot run a second animation clock.
	if recipe == "roast_meat":
		var skewer := spit.get_node("SpitSkewer") as Node3D
		skewer.rotation.x = amount * TAU * 3.0
		for child in skewer.get_children():
			if String(child.name).begins_with("MeatChunk"):
				var material := (child as MeshInstance3D).material_override as StandardMaterial3D
				material.albedo_color = Color(0.48, 0.16, 0.12).lerp(Color(0.27, 0.13, 0.055), smoothstep(0.08, 0.98, amount))
				for char_mark in child.get_children():
					(char_mark as Node3D).visible = amount > 0.38
	else:
		var liquid := pot.get_node("SoupSurface") as MeshInstance3D
		var broth := liquid.material_override as StandardMaterial3D
		broth.albedo_color = Color(0.38, 0.27, 0.10) if recipe == "mushroom_soup" else Color(0.29, 0.125, 0.045)
		var spoon := pot.get_node("StirringSpoon") as Node3D
		var stirring_angle := amount * TAU * 4.0
		spoon.position = Vector3(sin(stirring_angle) * 0.075, 0.515, cos(stirring_angle) * 0.075)
		spoon.rotation = Vector3(0.18, -stirring_angle, 0.24)
		for index in 8:
			var bubble := pot.get_node("SoupBubble%d" % index) as Node3D
			var pulse := fposmod(amount * 7.0 + float(index) * 0.137, 1.0)
			var bubble_size := sin(pulse * PI) * (0.4 + amount * 0.6)
			bubble.scale = Vector3.ONE * maxf(0.02, bubble_size)
			bubble.position.y = 0.524 + sin(pulse * PI) * 0.012
		for index in 5:
			var food := pot.get_node("SoupIngredient%d" % index) as MeshInstance3D
			food.rotation.y = stirring_angle * 0.3 + float(index)
			var ingredient_material := food.material_override as StandardMaterial3D
			ingredient_material.albedo_color = Color(0.53, 0.42, 0.23) if recipe == "mushroom_soup" or index % 2 == 0 else Color(0.29, 0.13, 0.075)
	var steam := tools.get_node("CookingSteam") as Node3D
	steam.position.y = 0.16 if recipe == "roast_meat" else 0.20
	for index in 9:
		var puff := steam.get_node("SteamPuff%d" % index) as MeshInstance3D
		var rise := fposmod(amount * 4.5 + float(index) * 0.113, 1.0)
		var turn := float(index) * 2.39 + amount * 4.0
		puff.position = Vector3(cos(turn) * (0.04 + rise * 0.09), 0.43 + rise * 0.52, sin(turn) * (0.04 + rise * 0.09))
		puff.scale = Vector3(0.65 + rise * 0.60, 1.0 + rise * 0.55, 1.0) * (0.45 + rise * 0.60)
		var material := puff.material_override as StandardMaterial3D
		material.albedo_color.a = sin(rise * PI) * 0.095 * clampf(amount * 2.3, 0.0, 1.0)


static func _create_cooking_tools(camp: Node3D) -> Node3D:
	var tools := Node3D.new()
	tools.name = "CookingTools"
	tools.visible = false
	camp.add_child(tools)
	var iron := _material(Color(0.085, 0.08, 0.068))
	iron.metallic = 0.65
	iron.roughness = 0.62
	var wood := _material(Color(0.29, 0.17, 0.08), WOOD)
	_build_roasting_spit(tools, iron, wood)
	_build_soup_pot(tools, iron, wood)
	var steam := Node3D.new()
	steam.name = "CookingSteam"
	tools.add_child(steam)
	# Radially feathered alpha removes the hard silhouettes of solid steam
	# meshes. Small billboards read as pale wisps from any viewing direction.
	var falloff := Gradient.new()
	falloff.offsets = PackedFloat32Array([0.0, 0.22, 0.52, 0.78, 1.0])
	falloff.colors = PackedColorArray([Color(1.0, 1.0, 1.0, 0.80), Color(1.0, 1.0, 1.0, 0.51), Color(1.0, 1.0, 1.0, 0.19), Color(1.0, 1.0, 1.0, 0.045), Color(1.0, 1.0, 1.0, 0.0)])
	var steam_texture := GradientTexture2D.new()
	steam_texture.gradient = falloff
	steam_texture.width = 64
	steam_texture.height = 64
	steam_texture.fill = GradientTexture2D.FILL_RADIAL
	steam_texture.fill_from = Vector2(0.5, 0.5)
	steam_texture.fill_to = Vector2(1.0, 0.5)
	for index in 9:
		var material := _material(Color(0.82, 0.84, 0.79, 0.0))
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		material.billboard_keep_scale = true
		material.albedo_texture = steam_texture
		material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
		var puff := MeshInstance3D.new()
		puff.name = "SteamPuff%d" % index
		var quad := QuadMesh.new()
		quad.size = Vector2(0.11, 0.17)
		puff.mesh = quad
		puff.material_override = material
		puff.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		steam.add_child(puff)
	return tools


static func _build_roasting_spit(tools: Node3D, iron: StandardMaterial3D, wood: StandardMaterial3D) -> void:
	var spit := Node3D.new()
	spit.name = "RoastingSpit"
	spit.visible = false
	tools.add_child(spit)
	for side in [-1.0, 1.0]:
		_cooking_rod(spit, "SpitSupport", Vector3(side * 0.38, 0.08, 0.0), Vector3(side * 0.38, 0.54, 0.0), 0.025, wood)
		_cooking_rod(spit, "SpitFork", Vector3(side * 0.38, 0.42, 0.0), Vector3(side * 0.38, 0.57, 0.075), 0.015, wood)
	var skewer := Node3D.new()
	skewer.name = "SpitSkewer"
	skewer.position.y = 0.52
	spit.add_child(skewer)
	_cooking_rod(skewer, "IronSkewer", Vector3(-0.46, 0.0, 0.0), Vector3(0.47, 0.0, 0.0), 0.009, iron)
	_cooking_rod(skewer, "SkewerTurnHandle", Vector3(0.45, 0.0, 0.0), Vector3(0.45, 0.075, 0.0), 0.016, wood)
	var char_material := _material(Color(0.105, 0.045, 0.018))
	for index in 3:
		var meat := _cooking_sphere("MeatChunk%d" % index, 0.085, _material(Color(0.48, 0.16, 0.12)))
		meat.position.x = (float(index) - 1.0) * 0.16
		meat.scale = Vector3(0.9, 0.82 + float(index % 2) * 0.18, 1.24)
		skewer.add_child(meat)
		for stripe in 3:
			var line := MeshInstance3D.new()
			line.name = "RoastedCharStripe%d" % stripe
			var mark := BoxMesh.new()
			mark.size = Vector3(0.011, 0.004, 0.095)
			line.mesh = mark
			line.material_override = char_material
			line.position = Vector3((float(stripe) - 1.0) * 0.034, 0.071, 0.0)
			line.visible = false
			meat.add_child(line)


static func _build_soup_pot(tools: Node3D, iron: StandardMaterial3D, wood: StandardMaterial3D) -> void:
	var pot := Node3D.new()
	pot.name = "SoupPot"
	pot.visible = false
	tools.add_child(pot)
	for index in 3:
		var angle := float(index) * TAU / 3.0
		_cooking_rod(pot, "PotStand%d" % index, Vector3(cos(angle) * 0.25, 0.08, sin(angle) * 0.25), Vector3(cos(angle) * 0.18, 0.36, sin(angle) * 0.18), 0.014, iron)
	var body := MeshInstance3D.new()
	body.name = "CookingPot"
	var bowl := CylinderMesh.new()
	bowl.top_radius = 0.225
	bowl.bottom_radius = 0.16
	bowl.height = 0.23
	bowl.radial_segments = 24
	bowl.cap_top = false
	body.mesh = bowl
	var bowl_material := iron.duplicate() as StandardMaterial3D
	bowl_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	body.material_override = bowl_material
	body.position.y = 0.41
	pot.add_child(body)
	var rim := MeshInstance3D.new()
	rim.name = "PotRim"
	var ring := TorusMesh.new()
	ring.inner_radius = 0.213
	ring.outer_radius = 0.235
	ring.rings = 24
	ring.ring_segments = 8
	rim.mesh = ring
	rim.material_override = iron
	rim.position.y = 0.527
	pot.add_child(rim)
	for side in [-1.0, 1.0]:
		var handle := MeshInstance3D.new()
		handle.name = "PotHandle"
		var loop := TorusMesh.new()
		loop.inner_radius = 0.033
		loop.outer_radius = 0.047
		loop.rings = 12
		loop.ring_segments = 6
		handle.mesh = loop
		handle.material_override = iron
		handle.position = Vector3(side * 0.243, 0.47, 0.0)
		handle.rotation.z = PI * 0.5
		pot.add_child(handle)
	var liquid := MeshInstance3D.new()
	liquid.name = "SoupSurface"
	var soup := CylinderMesh.new()
	soup.top_radius = 0.207
	soup.bottom_radius = 0.207
	soup.height = 0.012
	soup.radial_segments = 24
	liquid.mesh = soup
	liquid.material_override = _material(Color(0.38, 0.27, 0.10))
	liquid.position.y = 0.513
	pot.add_child(liquid)
	for index in 8:
		var angle := float(index) * 2.39
		var bubble := _cooking_sphere("SoupBubble%d" % index, 0.018, _material(Color(0.55, 0.39, 0.17)))
		bubble.position = Vector3(cos(angle) * 0.15, 0.529, sin(angle) * 0.15)
		pot.add_child(bubble)
	for index in 5:
		var angle := float(index) * 2.39 + 0.7
		var ingredient := _cooking_sphere("SoupIngredient%d" % index, 0.025, _material(Color(0.53, 0.42, 0.23)))
		ingredient.position = Vector3(cos(angle) * 0.12, 0.521, sin(angle) * 0.12)
		ingredient.scale = Vector3(1.25, 0.4, 0.75)
		pot.add_child(ingredient)
	var spoon := Node3D.new()
	spoon.name = "StirringSpoon"
	pot.add_child(spoon)
	_cooking_rod(spoon, "WoodenLadleStem", Vector3.ZERO, Vector3(0.0, 0.38, 0.0), 0.012, wood)
	var ladle := _cooking_sphere("WoodenLadleBowl", 0.047, wood)
	ladle.scale = Vector3(0.72, 0.24, 1.05)
	spoon.add_child(ladle)


static func _cooking_sphere(node_name: String, radius: float, material: StandardMaterial3D) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 10
	mesh.rings = 5
	instance.mesh = mesh
	instance.material_override = material
	return instance


static func _cooking_rod(parent: Node3D, node_name: String, start: Vector3, end: Vector3, radius: float, material: StandardMaterial3D) -> void:
	var rod := MeshInstance3D.new()
	rod.name = node_name
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = start.distance_to(end)
	mesh.radial_segments = 10
	rod.mesh = mesh
	rod.material_override = material
	var direction := start.direction_to(end)
	var reference := Vector3.UP if absf(direction.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	var axis_x := reference.cross(direction).normalized()
	rod.transform = Transform3D(Basis(axis_x, direction, axis_x.cross(direction).normalized()), (start + end) * 0.5)
	parent.add_child(rod)


static func _material(color_value: Color, texture: Texture2D = null) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color_value
	material.roughness = 0.94
	if texture != null:
		material.albedo_texture = texture
		material.uv1_triplanar = true
		material.uv1_scale = Vector3.ONE * 3.0
		material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return material
