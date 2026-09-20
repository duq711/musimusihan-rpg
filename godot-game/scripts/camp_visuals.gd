extends RefCounted
class_name CampVisuals

const WOOD: Texture2D = preload("res://assets/ai/materials/ancient_oak.png")
const STONE: Texture2D = preload("res://assets/ai/materials/wet_flagstone.png")
const FLAME_VISUALS := preload("res://scripts/flame_visuals.gd")
const FLAME: Texture2D = preload("res://assets/ai/vfx/torch_flame.png")
const AGED_SURFACES := preload("res://scripts/dark_fantasy_materials.gd")
const COAL: Texture2D = preload("res://assets/ai/materials/concept_ember_coal.png")
const TENT_POSITION := Vector3(1.05, 0.0, -0.35)
const TENT_SIZE := Vector3(1.10, 1.0, 1.70)
const SEAT_POSITION := Vector3(0.0, 0.0, 1.10)
const WORLD_LAYER := 2
const INTERACT_LAYER := 16
static var _food_noise: NoiseTexture2D


static func create_camp(interaction_owner: Node = null) -> Node3D:
	var camp := Node3D.new()
	camp.name = "CampVisual"
	var stone_material := AGED_SURFACES.stone(Color(0.19, 0.205, 0.20), 3.2)
	var wood_material := AGED_SURFACES.create("oak", Color(0.85, 0.85, 0.85), COAL, 1.4)
	wood_material.normal_scale = 0.60
	wood_material.metallic_specular = 0.15
	var cloth_material := AGED_SURFACES.linen(Color(0.23, 0.215, 0.18), 7.0)
	for index in range(9):
		var stone := MeshInstance3D.new()
		stone.name = "FireRingStone%d" % index
		var sphere := SphereMesh.new()
		sphere.radius = 0.095
		sphere.height = 0.15
		sphere.radial_segments = 7
		sphere.rings = 4
		stone.mesh = _fractured_stone(sphere, index)
		stone.material_override = stone_material
		var angle := index * TAU / 9.0
		stone.position = Vector3(cos(angle) * 0.33, 0.06, sin(angle) * 0.33)
		stone.rotation = Vector3(0.10 * sin(float(index) * 3.0), angle, 0.12 * cos(float(index)))
		stone.scale = Vector3(1.18 + 0.12 * sin(float(index)), 0.83 + 0.10 * cos(float(index) * 2.4), 0.96)
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
	bed.mesh = create_folded_pad(Vector3(0.34, 0.07, 0.82))
	bed.material_override = cloth_material
	bed.position = TENT_POSITION + Vector3(0.0, 0.065, 0.14)
	camp.add_child(bed)
	_add_bedroll_stitches(bed, Vector3(0.34, 0.07, 0.82))
	var carrying_strap := MeshInstance3D.new()
	carrying_strap.name = "BedrollLeatherCarryingStrap"
	var strap_loop := TorusMesh.new()
	strap_loop.inner_radius = 0.17
	strap_loop.outer_radius = 0.183
	strap_loop.rings = 32
	strap_loop.ring_segments = 4
	carrying_strap.mesh = strap_loop
	carrying_strap.material_override = AGED_SURFACES.leather()
	carrying_strap.position = Vector3(0.208, -0.018, 0.0)
	carrying_strap.scale = Vector3(0.34, 0.45, 1.0)
	bed.add_child(carrying_strap)
	var pillow := MeshInstance3D.new()
	pillow.name = "RolledBlanket"
	var roll := CylinderMesh.new()
	roll.top_radius = 0.075
	roll.bottom_radius = 0.075
	roll.height = 0.34
	roll.radial_segments = 24
	pillow.mesh = roll
	pillow.material_override = cloth_material
	pillow.position = TENT_POSITION + Vector3(0.0, 0.12, -0.29)
	pillow.rotation.z = PI / 2.0
	camp.add_child(pillow)
	for side in [-1.0, 1.0]:
		for ring_index in 3:
			var fold := MeshInstance3D.new()
			fold.name = "RolledBlanketFold_%s_%d" % [str(side), ring_index]
			var folded_ring := TorusMesh.new()
			folded_ring.inner_radius = 0.015 + float(ring_index) * 0.018
			folded_ring.outer_radius = 0.023 + float(ring_index) * 0.018
			folded_ring.rings = 24
			folded_ring.ring_segments = 5
			fold.mesh = folded_ring
			fold.material_override = cloth_material
			fold.position.y = side * 0.174
			pillow.add_child(fold)
	var flame := Sprite3D.new()
	flame.name = "Flame"
	flame.texture = FLAME
	flame.pixel_size = 0.00042
	flame.position.y = 0.10 + float(FLAME.get_height()) * flame.pixel_size * 0.46
	flame.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	flame.alpha_cut = SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS
	flame.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	flame.double_sided = true
	flame.shaded = false
	camp.add_child(flame)
	FLAME_VISUALS.attach(flame)
	var light := OmniLight3D.new()
	light.name = "CampfireLight"
	light.position = Vector3(0.0, 0.45, 0.0)
	light.light_color = Color(1.0, 0.52, 0.19)
	light.light_energy = 3.1
	light.omni_range = 6.0
	light.shadow_enabled = true
	camp.add_child(light)
	_create_cooking_tools(camp)
	_create_tent(camp, interaction_owner)
	var seat := Marker3D.new()
	seat.name = "CampSeat"
	seat.position = SEAT_POSITION
	camp.add_child(seat)
	return camp


static func _create_tent(camp: Node3D, interaction_owner: Node) -> Node3D:
	var tent := Node3D.new()
	tent.name = "Tent"
	tent.position = TENT_POSITION
	camp.add_child(tent)
	var cloth := AGED_SURFACES.linen(Color(0.35, 0.30, 0.22), 5.0)
	cloth.cull_mode = BaseMaterial3D.CULL_DISABLED
	var canvas := MeshInstance3D.new()
	canvas.name = "WeatheredCanvas"
	canvas.mesh = _tent_canvas_mesh()
	canvas.material_override = cloth
	tent.add_child(canvas)
	var poles := AGED_SURFACES.old_oak(Color(0.28, 0.22, 0.14), 3.0)
	var seam := AGED_SURFACES.linen(Color(0.20, 0.17, 0.12), 6.0)
	for end: float in [-0.81, 0.81]:
		_cooking_rod(tent, "TentPoleBack" if end < 0.0 else "TentPoleFront", Vector3(0.0, 0.02, end), Vector3(0.0, 0.985, end), 0.018, poles)
		for side: float in [-1.0, 1.0]:
			_cooking_rod(tent, "CanvasHem_%s_%s" % [str(end), str(side)], Vector3(0.0, 0.992, end), Vector3(side * 0.54, 0.04, end), 0.006, seam)
			_cooking_rod(tent, "TentStake_%s_%s" % [str(end), str(side)], Vector3(side * 0.525, 0.01, end), Vector3(side * 0.535, 0.115, end - 0.025), 0.012, poles)
	_cooking_rod(tent, "TentRidgePole", Vector3(0.0, 0.97, -0.82), Vector3(0.0, 0.97, 0.82), 0.016, poles)
	# The box matches the reserved placement volume. The interaction area is
	# separate so the player can aim at any canvas panel to sit by the fire.
	var body := StaticBody3D.new()
	body.name = "TentBody"
	body.collision_layer = WORLD_LAYER
	body.collision_mask = 0
	var collider := CollisionShape3D.new()
	collider.name = "TentCollision"
	var shape := BoxShape3D.new()
	shape.size = TENT_SIZE
	collider.shape = shape
	collider.position.y = TENT_SIZE.y * 0.5
	body.add_child(collider)
	tent.add_child(body)
	if is_instance_valid(interaction_owner):
		var area := Area3D.new()
		area.name = "TentInteraction"
		area.collision_layer = INTERACT_LAYER
		area.collision_mask = 0
		area.monitoring = false
		area.monitorable = false
		area.set_meta("interaction_owner", interaction_owner)
		var interaction_shape := CollisionShape3D.new()
		var interaction_box := BoxShape3D.new()
		interaction_box.size = TENT_SIZE + Vector3(0.10, 0.06, 0.10)
		interaction_shape.shape = interaction_box
		interaction_shape.position.y = TENT_SIZE.y * 0.5
		area.add_child(interaction_shape)
		tent.add_child(area)
	return tent


static func _tent_canvas_mesh() -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Low A-frame canvas with small uneven folds, rather than a rigid prism.
	for side: float in [-1.0, 1.0]:
		for row in 12:
			for column in 8:
				var u0 := float(column) / 8.0
				var u1 := float(column + 1) / 8.0
				var v0 := float(row) / 12.0
				var v1 := float(row + 1) / 12.0
				_cloth_quad(surface, _tent_point(side, u0, v0), _tent_point(side, u1, v0), _tent_point(side, u1, v1), _tent_point(side, u0, v1), side < 0.0)
	# Closed back, and two tied-back door flaps facing the camp seat (+Z).
	_tent_triangle(surface, Vector3(-0.54, 0.035, -0.84), Vector3(0.0, 0.992, -0.84), Vector3(0.54, 0.035, -0.84))
	for side: float in [-1.0, 1.0]:
		_tent_triangle(surface, Vector3(0.0, 0.992, 0.84), Vector3(side * 0.54, 0.035, 0.84), Vector3(side * 0.29, 0.035, 0.805))
	surface.generate_normals()
	return surface.commit()


static func _tent_point(side: float, u: float, v: float) -> Vector3:
	var sag := sin(u * PI) * sin(v * PI) * 0.06
	var fold := sin(v * 39.0 + u * 5.0) * sin(u * PI) * 0.013
	return Vector3(side * u * 0.55, lerpf(0.998, 0.025, u) - sag + fold, lerpf(-0.85, 0.85, v))


static func _tent_triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	for vertex: Vector3 in [a, b, c]:
		surface.set_uv(Vector2(vertex.x, vertex.y))
		surface.add_vertex(vertex)


static func create_preview() -> Node3D:
	var preview := Node3D.new()
	preview.name = "CampPlacementPreview"
	var fill := _preview_material(0.24)
	var outline := _preview_material(0.84)
	preview.set_meta("fill_material", fill)
	preview.set_meta("outline_material", outline)
	var canvas := MeshInstance3D.new()
	canvas.name = "TentGhost"
	canvas.mesh = _tent_canvas_mesh()
	canvas.material_override = fill
	canvas.position = TENT_POSITION
	canvas.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	preview.add_child(canvas)
	for end: float in [-0.85, 0.85]:
		for side: float in [-1.0, 1.0]:
			_cooking_rod(preview, "TentOutline_%s_%s" % [str(end), str(side)], TENT_POSITION + Vector3(0.0, 1.0, end), TENT_POSITION + Vector3(side * 0.55, 0.025, end), 0.012, outline)
	_cooking_rod(preview, "RidgeOutline", TENT_POSITION + Vector3(0.0, 1.0, -0.85), TENT_POSITION + Vector3(0.0, 1.0, 0.85), 0.012, outline)
	for side: float in [-1.0, 1.0]:
		_cooking_rod(preview, "GroundOutline_%s" % str(side), TENT_POSITION + Vector3(side * 0.55, 0.025, -0.85), TENT_POSITION + Vector3(side * 0.55, 0.025, 0.85), 0.01, outline)
	var ring := MeshInstance3D.new()
	ring.name = "FireRingGhost"
	var torus := TorusMesh.new()
	torus.inner_radius = 0.28
	torus.outer_radius = 0.40
	torus.rings = 32
	torus.ring_segments = 6
	ring.mesh = torus
	ring.position.y = 0.065
	ring.material_override = fill
	preview.add_child(ring)
	for side: float in [-1.0, 1.0]:
		_cooking_rod(preview, "FirewoodGhost_%s" % str(side), Vector3(-0.18, 0.08, side * 0.18), Vector3(0.18, 0.08, -side * 0.18), 0.04, outline)
	for child in preview.get_children():
		if child is GeometryInstance3D:
			child.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	set_preview_valid(preview, false)
	return preview


static func _preview_material(alpha: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = Color(0.82, 0.13, 0.09, alpha)
	return material


static func set_preview_valid(preview: Node3D, valid: bool) -> void:
	if not is_instance_valid(preview):
		return
	if preview.has_meta("placement_valid") and bool(preview.get_meta("placement_valid")) == valid:
		return
	preview.set_meta("placement_valid", valid)
	var tint := Color(0.25, 0.88, 0.37) if valid else Color(0.94, 0.19, 0.14)
	for key: String in ["fill_material", "outline_material"]:
		var material := preview.get_meta(key, null) as StandardMaterial3D
		if material != null:
			tint.a = material.albedo_color.a
			material.albedo_color = tint


static func _fractured_stone(source: SphereMesh, index: int) -> ArrayMesh:
	var arrays := source.get_mesh_arrays()
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	for vertex_index in vertices.size():
		var vertex := vertices[vertex_index]
		var variation := 1.0 + 0.11 * sin(vertex.x * 77.0 + vertex.y * 59.0 + vertex.z * 83.0 + float(index) * 2.3)
		vertices[vertex_index] = vertex * variation
	arrays[Mesh.ARRAY_VERTEX] = vertices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var surface := SurfaceTool.new()
	surface.create_from(mesh, 0)
	surface.generate_normals()
	return surface.commit()


static func create_folded_pad(size_value: Vector3) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	const COLUMNS := 8
	const ROWS := 24
	for face in [-1.0, 1.0]:
		for row in ROWS:
			for column in COLUMNS:
				var x0 := float(column) / COLUMNS * 2.0 - 1.0
				var x1 := float(column + 1) / COLUMNS * 2.0 - 1.0
				var z0 := float(row) / ROWS * 2.0 - 1.0
				var z1 := float(row + 1) / ROWS * 2.0 - 1.0
				_cloth_quad(surface, _pad_point(x0, z0, size_value, face), _pad_point(x1, z0, size_value, face), _pad_point(x1, z1, size_value, face), _pad_point(x0, z1, size_value, face), face < 0.0)
	for edge in [-1.0, 1.0]:
		for row in ROWS:
			var z0 := float(row) / ROWS * 2.0 - 1.0
			var z1 := float(row + 1) / ROWS * 2.0 - 1.0
			_cloth_quad(surface, _pad_point(edge, z0, size_value, -1.0), _pad_point(edge, z1, size_value, -1.0), _pad_point(edge, z1, size_value, 1.0), _pad_point(edge, z0, size_value, 1.0), edge < 0.0)
		for column in COLUMNS:
			var x0 := float(column) / COLUMNS * 2.0 - 1.0
			var x1 := float(column + 1) / COLUMNS * 2.0 - 1.0
			_cloth_quad(surface, _pad_point(x0, edge, size_value, -1.0), _pad_point(x1, edge, size_value, -1.0), _pad_point(x1, edge, size_value, 1.0), _pad_point(x0, edge, size_value, 1.0), edge > 0.0)
	surface.generate_normals()
	return surface.commit()


static func _pad_point(x: float, z: float, size_value: Vector3, face: float) -> Vector3:
	var margin := (1.0 - pow(absf(x), 6.0)) * (1.0 - pow(absf(z), 10.0))
	var fold := (sin(z * 36.0 + x * 3.0) + sin(z * 19.0 - x * 8.0) * 0.5) * size_value.y * 0.085 * margin
	var height := size_value.y * (0.24 + margin * 0.25) * face
	return Vector3(x * size_value.x * 0.5 * (0.965 + sin((z + 1.0) * PI * 0.5) * 0.035), height + fold, z * size_value.z * 0.5)


static func _cloth_quad(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, flip: bool) -> void:
	for vertex in [a, b, c, a, c, d] if flip else [a, c, b, a, d, c]:
		surface.set_uv(Vector2(vertex.x, vertex.z))
		surface.add_vertex(vertex)


static func _add_bedroll_stitches(bed: Node3D, size_value: Vector3) -> void:
	var stitches := MultiMeshInstance3D.new()
	stitches.name = "BedrollEdgeStitches"
	var stitch_mesh := BoxMesh.new()
	stitch_mesh.size = Vector3(0.011, 0.004, 0.003)
	var instances := MultiMesh.new()
	instances.transform_format = MultiMesh.TRANSFORM_3D
	instances.mesh = stitch_mesh
	instances.instance_count = 60
	for side_index in 2:
		var side := -1.0 if side_index == 0 else 1.0
		for index in 30:
			var at := _pad_point(side * 0.95, -0.95 + float(index) / 29.0 * 1.9, size_value, 1.0)
			at.y += 0.0025
			instances.set_instance_transform(side_index * 30 + index, Transform3D(Basis(Vector3.UP, 0.4 * side), at))
	stitches.multimesh = instances
	stitches.material_override = AGED_SURFACES.linen(Color(0.32, 0.29, 0.23))
	bed.add_child(stitches)


static func animate(camp: Node3D, elapsed: float, warmth: int) -> void:
	if not is_instance_valid(camp):
		return
	var strength := 0.35 + 0.65 * clampf(float(warmth) / 3.0, 0.0, 1.0)
	var pulse := 1.0 + sin(elapsed * 13.0) * 0.06 + sin(elapsed * 23.0) * 0.025
	var flame := camp.get_node("Flame") as Node3D
	flame.scale = Vector3(1.0 / pulse, pulse, 1.0) * strength
	# Keep the visible foot of the flame on the logs even as warmth changes.
	flame.position.y = 0.10 + float(FLAME.get_height()) * (flame as Sprite3D).pixel_size * 0.46 * flame.scale.y
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
				material.albedo_color = Color(0.29, 0.145, 0.10).lerp(Color(0.15, 0.10, 0.065), smoothstep(0.08, 0.98, amount))
				for char_mark in child.get_children():
					(char_mark as Node3D).visible = amount > 0.38
	else:
		var liquid := pot.get_node("SoupSurface") as MeshInstance3D
		var broth := liquid.material_override as StandardMaterial3D
		broth.albedo_color = Color(0.39, 0.325, 0.22) if recipe == "mushroom_soup" else Color(0.23, 0.13, 0.075)
		(pot.get_node("MushroomSlices") as Node3D).visible = recipe == "mushroom_soup"
		(pot.get_node("StewMorsels") as Node3D).visible = recipe == "trail_stew"
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
		material.albedo_color.a = sin(rise * PI) * 0.15 * clampf(amount * 2.3, 0.0, 1.0)


static func _create_cooking_tools(camp: Node3D) -> Node3D:
	var tools := Node3D.new()
	tools.name = "CookingTools"
	tools.visible = false
	camp.add_child(tools)
	var iron := AGED_SURFACES.pitted_iron(Color(0.29, 0.285, 0.265), 4.0)
	var wood := AGED_SURFACES.old_oak(Color(0.40, 0.39, 0.34), 3.0)
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
		material.albedo_texture = FLAME_VISUALS.steam_texture()
		material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
		var puff := MeshInstance3D.new()
		puff.name = "SteamPuff%d" % index
		var quad := QuadMesh.new()
		quad.size = Vector2(0.17, 0.26)
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
		var meat := _cooking_sphere("MeatChunk%d" % index, 0.085, _food_material(Color(0.29, 0.145, 0.10), 18.0))
		meat.mesh = _fractured_stone(meat.mesh as SphereMesh, index + 21)
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
	bowl.radial_segments = 32
	bowl.rings = 10
	bowl.cap_top = false
	var arrays := bowl.get_mesh_arrays()
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	for vertex in vertices.size():
		var point := vertices[vertex]
		var t := (point.y + 0.115) / 0.23
		var radial := Vector2(point.x, point.z).normalized()
		var radius := 0.16 + 0.065 * sin(t * PI * 0.5) + 0.017 * sin(t * PI)
		vertices[vertex] = Vector3(radial.x * radius, point.y, radial.y * radius) if radial.length() > 0.01 else point
	arrays[Mesh.ARRAY_VERTEX] = vertices
	body.mesh = preload("res://scripts/dungeon_concept_visual.gd")._rebuild_normals(arrays)
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
	liquid.material_override = _food_material(Color(0.39, 0.325, 0.22), 9.0)
	(liquid.material_override as StandardMaterial3D).roughness = 0.54
	(liquid.material_override as StandardMaterial3D).uv1_scale = Vector3.ONE * 1.7
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
	var mushrooms := Node3D.new()
	mushrooms.name = "MushroomSlices"
	pot.add_child(mushrooms)
	var morsels := Node3D.new()
	morsels.name = "StewMorsels"
	pot.add_child(morsels)
	var herbs := Node3D.new()
	herbs.name = "SoupHerbs"
	pot.add_child(herbs)
	var slice_material := _food_material(Color(0.38, 0.33, 0.245), 24.0)
	slice_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var herb_material := _material(Color(0.09, 0.12, 0.065))
	for index in 16:
		var angle := float(index) * 2.39996
		var radius := sqrt((float(index) + 0.5) / 16.0) * 0.175
		var at := Vector3(cos(angle) * radius, 0.52, sin(angle) * radius)
		var slice := MeshInstance3D.new()
		slice.name = "MushroomSlice_%d" % index
		slice.mesh = _mushroom_slice_mesh()
		slice.material_override = slice_material
		slice.position = at
		slice.rotation.y = angle
		mushrooms.add_child(slice)
		var chunk := _cooking_sphere("StewMorsel_%d" % index, 0.024, _food_material(Color(0.25, 0.15, 0.085) if index % 3 else Color(0.29, 0.19, 0.105), 26.0))
		chunk.mesh = _fractured_stone(chunk.mesh as SphereMesh, index + 51)
		chunk.position = at
		chunk.scale = Vector3(1, 0.43, 0.86)
		morsels.add_child(chunk)
		var leaf := MeshInstance3D.new()
		leaf.name = "ChoppedHerb_%d" % index
		var leaf_mesh := BoxMesh.new()
		leaf_mesh.size = Vector3(0.011, 0.0015, 0.0035)
		leaf.mesh = leaf_mesh
		leaf.material_override = herb_material
		leaf.position = Vector3(sin(angle) * radius, 0.521, cos(angle) * radius)
		leaf.rotation.y = angle
		herbs.add_child(leaf)
	var spoon := Node3D.new()
	spoon.name = "StirringSpoon"
	pot.add_child(spoon)
	_cooking_rod(spoon, "WoodenLadleStem", Vector3.ZERO, Vector3(0.0, 0.38, 0.0), 0.012, wood)
	var ladle := _cooking_sphere("WoodenLadleBowl", 0.047, wood)
	ladle.scale = Vector3(0.72, 0.24, 1.05)
	spoon.add_child(ladle)


static func _food_material(tint: Color, scale_value: float) -> StandardMaterial3D:
	if _food_noise == null:
		var noise := FastNoiseLite.new()
		noise.seed = 947
		noise.frequency = 0.06
		noise.fractal_octaves = 4
		var ramp := Gradient.new()
		ramp.colors = PackedColorArray([Color(0.69, 0.68, 0.65), Color(0.86, 0.85, 0.81)])
		_food_noise = NoiseTexture2D.new()
		_food_noise.width = 128
		_food_noise.height = 128
		_food_noise.seamless = true
		_food_noise.noise = noise
		_food_noise.color_ramp = ramp
	var material := _material(tint, _food_noise)
	material.uv1_scale = Vector3.ONE * scale_value
	return material


static func _mushroom_slice_mesh() -> ArrayMesh:
	var outline := PackedVector2Array()
	for index in 13:
		var angle := PI - float(index) / 12.0 * PI
		outline.append(Vector2(cos(angle) * 0.024, -sin(angle) * 0.020))
	outline.append_array(PackedVector2Array([Vector2(0.007, 0), Vector2(0.008, 0.023), Vector2(-0.008, 0.023), Vector2(-0.007, 0)]))
	var triangles := Geometry2D.triangulate_polygon(outline)
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for side in [-1.0, 1.0]:
		for index in range(0, triangles.size(), 3):
			for corner in 3:
				var p := outline[triangles[index + (corner if side < 0 else 2 - corner)]]
				surface.add_vertex(Vector3(p.x, side * 0.004, p.y))
	for index in outline.size():
		var a := outline[index]
		var b := outline[(index + 1) % outline.size()]
		for p in [Vector3(a.x, -0.004, a.y), Vector3(b.x, -0.004, b.y), Vector3(b.x, 0.004, b.y), Vector3(a.x, -0.004, a.y), Vector3(b.x, 0.004, b.y), Vector3(a.x, 0.004, a.y)]:
			surface.add_vertex(p)
	surface.generate_normals()
	return surface.commit()


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
