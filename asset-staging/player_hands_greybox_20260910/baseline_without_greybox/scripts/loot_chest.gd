extends StaticBody3D
class_name DungeonLootChest

signal open_requested(chest: DungeonLootChest)

const PLAYER_LAYER := 1
const WORLD_LAYER := 2
const ENEMY_LAYER := 4
const INTERACT_LAYER := 16
const OPEN_DURATION := 1.2

const CHEST_SCENE := preload("res://assets/3d/dark_fantasy/reliquary_chest.glb")
const RUNE_TEXTURE := preload("res://assets/ai/vfx/rune_trap.png")
const ANCIENT_OAK_TEXTURE := preload("res://assets/ai/materials/ancient_oak.png")
const PITTED_IRON_TEXTURE := preload("res://assets/ai/materials/pitted_black_iron.png")
const AGED_SURFACES := preload("res://scripts/dark_fantasy_materials.gd")

enum ChestState { CLOSED, OPENING, OPENED }

var container := LootContainer.new()
var opened := false
var state := ChestState.CLOSED
var opening_player: DungeonPlayer

var lid_pivot: Node3D
var interaction_area: Area3D
var rune_material: StandardMaterial3D
var _lid_closed_rotation := Vector3.ZERO
var _lid_tween: Tween
var _hand_approach := "front"


func configure(title_text: String, item_stacks: Array, subtitle_text := "검은 성물실") -> DungeonLootChest:
	container.configure(title_text, item_stacks, subtitle_text, 20)
	return self


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("loot_chest")
	name = "LootChest"
	collision_layer = WORLD_LAYER
	collision_mask = PLAYER_LAYER | ENEMY_LAYER
	_build_collision()
	_build_visuals()
	_build_interaction_area()
	container.changed.connect(_on_container_changed)


func _build_collision() -> void:
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.8, 1.05, 1.2)
	collision.shape = shape
	collision.position.y = 0.53
	add_child(collision)


func _build_visuals() -> void:
	var chest_model := CHEST_SCENE.instantiate() as Node3D
	chest_model.name = "ReliquaryChestVisual"
	chest_model.scale = Vector3(1.42, 1.18, 1.42)
	add_child(chest_model)
	_disable_imported_collisions(chest_model)
	apply_concept_surface(chest_model)

	lid_pivot = chest_model.find_child("LidPivot", true, false) as Node3D
	if lid_pivot == null:
		lid_pivot = Node3D.new()
		lid_pivot.name = "LidPivot"
		lid_pivot.position = Vector3(0, 0.85, 0.54)
		chest_model.add_child(lid_pivot)
	var lid_parts: Array[Node3D] = []
	_collect_lid_parts(chest_model, lid_parts)
	for part in lid_parts:
		if part != lid_pivot and not lid_pivot.is_ancestor_of(part):
			var source_transform := _transform_to_ancestor(part, chest_model)
			var target_transform := _transform_to_ancestor(lid_pivot, chest_model)
			part.owner = null
			part.reparent(lid_pivot, false)
			part.transform = target_transform.affine_inverse() * source_transform
	_lid_closed_rotation = lid_pivot.rotation

	rune_material = _material(Color(0.17, 0.26, 0.235, 0.92), 0.86, 0.18)
	rune_material.emission_enabled = true
	rune_material.emission = Color(0.025, 0.10, 0.075)
	rune_material.emission_energy_multiplier = 0.35
	rune_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rune_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	rune_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	rune_material.albedo_texture = RUNE_TEXTURE
	rune_material.emission_texture = RUNE_TEXTURE
	var rune_quad := QuadMesh.new()
	rune_quad.size = Vector2(0.12, 0.12)
	var rune := MeshInstance3D.new()
	rune.name = "AISealRune"
	rune.mesh = rune_quad
	rune.material_override = rune_material
	rune.position = Vector3(0, 0.69, -0.617)
	add_child(rune)
	rune.set_meta("concept_reference", "reliquary_chest")


static func apply_concept_surface(chest_model: Node3D) -> void:
	# The six-view reference calls for vertical oak boards, riveted strapwork
	# and underfloor braces. Keep the imported lid parts/contact frames intact.
	if chest_model.has_meta("dark_fantasy_joinery"):
		return
	chest_model.set_meta("dark_fantasy_joinery", true)
	var old_oak := AGED_SURFACES.old_oak(Color(0.42, 0.455, 0.445), 2.0)
	var black_iron := AGED_SURFACES.pitted_iron(Color(0.22, 0.24, 0.235), 3.1)
	_apply_material_to_prefix(chest_model, ["ChestBody", "FrontPlank", "BackPlank", "LidSlat"], old_oak)
	_apply_material_to_prefix(chest_model, ["LidBand", "FrontCornerBand", "SideCornerBand", "BottomBand", "LockPlate", "RearHinge", "_MeshInstance3D"], black_iron)
	_set_meshes_visible_by_prefix(chest_model, ["LockRune", "FrontPlank", "BackPlank"], false)
	var joinery := Node3D.new()
	joinery.name = "AgedChestJoinery"
	chest_model.add_child(joinery)
	for side in [-1.0, 1.0]:
		for index in 10:
			var board := _box(Vector3(0.108, 0.57, 0.028), old_oak)
			board.name = "VerticalOakBoard_%s_%d" % [str(side), index]
			board.position = Vector3(-0.526 + float(index) * 0.117, 0.38, side * 0.382)
			joinery.add_child(board)
		for height in [0.12, 0.665]:
			var strap := _box(Vector3(1.20, 0.075, 0.038), black_iron)
			strap.name = "FrontRearIronStrap"
			strap.position = Vector3(0.0, height, side * 0.404)
			joinery.add_child(strap)
			for index in 9:
				_add_rivet(joinery, Vector3(-0.55 + float(index) * 0.1375, height, side * 0.428), Vector3.BACK * side, black_iron)
		for x in [-0.53, 0.53]:
			var upright := _box(Vector3(0.055, 0.55, 0.022), black_iron)
			upright.name = "UprightIronStrap"
			upright.position = Vector3(x, 0.39, side * 0.402)
			joinery.add_child(upright)
			for height in [0.24, 0.40, 0.55]:
				_add_rivet(joinery, Vector3(x, height, side * 0.416), Vector3.BACK * side, black_iron)
		for index in 6:
			var board := _box(Vector3(0.027, 0.57, 0.116), old_oak)
			board.name = "SideOakBoard_%s_%d" % [str(side), index]
			board.position = Vector3(side * 0.611, 0.38, -0.302 + float(index) * 0.121)
			joinery.add_child(board)
		for height in [0.12, 0.665]:
			var strap := _box(Vector3(0.035, 0.075, 0.79), black_iron)
			strap.name = "SideIronStrap"
			strap.position = Vector3(side * 0.625, height, 0.0)
			joinery.add_child(strap)
			for index in 6:
				_add_rivet(joinery, Vector3(side * 0.65, height, -0.32 + float(index) * 0.128), Vector3.RIGHT * side, black_iron)
	for x in [-0.47, 0.0, 0.47]:
		var brace := _box(Vector3(0.082, 0.064, 0.76), old_oak)
		brace.name = "UndersideOakBrace_%s" % str(x)
		brace.position = Vector3(x, 0.032, 0.0)
		joinery.add_child(brace)
	for band in chest_model.find_children("LidBand*", "MeshInstance3D", true, false):
		_add_rivet(band, Vector3(0.0, 0.073, 0.0), Vector3.UP, black_iron)
	for side in [-1.0, 1.0]:
		var cap := MeshInstance3D.new()
		cap.name = "LidEndcap_%s" % str(side)
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		for index in 16:
			var z0 := -0.399 + float(index) / 16.0 * 0.798
			var z1 := -0.399 + float(index + 1) / 16.0 * 0.798
			var h0 := 0.748 + sqrt(maxf(0.0, 1.0 - pow(z0 / 0.40, 2.0))) * 0.112
			var h1 := 0.748 + sqrt(maxf(0.0, 1.0 - pow(z1 / 0.40, 2.0))) * 0.112
			var a := Vector3(side * 0.608, 0.688, z0)
			var b := Vector3(side * 0.608, h0, z0)
			var c := Vector3(side * 0.608, h1, z1)
			var d := Vector3(side * 0.608, 0.688, z1)
			for vertex in [a, b, c, a, c, d] if side > 0.0 else [a, c, b, a, d, c]:
				surface.set_uv(Vector2(vertex.z, vertex.y))
				surface.add_vertex(vertex)
		surface.generate_normals()
		cap.mesh = surface.commit()
		var cap_material := old_oak.duplicate() as StandardMaterial3D
		cap_material.cull_mode = BaseMaterial3D.CULL_DISABLED
		cap.material_override = cap_material
		chest_model.add_child(cap)
	var lock := chest_model.find_child("LockPlate", true, false) as Node3D
	if lock != null:
		for x in [-0.073, 0.073]:
			for y in [-0.09, 0.09]:
				_add_rivet(lock, Vector3(x, y, -0.036), Vector3.FORWARD, black_iron)


static func _add_rivet(parent: Node3D, at: Vector3, normal: Vector3, material: StandardMaterial3D) -> void:
	# One draw submission per attachment frame; lid rivets retain the moving
	# band frame while the many static body rivets share one MultiMesh.
	var rivets := parent.get_node_or_null("HandForgedRivets") as MultiMeshInstance3D
	if rivets == null:
		rivets = MultiMeshInstance3D.new()
		rivets.name = "HandForgedRivets"
		var mesh_value := SphereMesh.new()
		mesh_value.radius = 0.012
		mesh_value.height = 0.014
		mesh_value.radial_segments = 8
		mesh_value.rings = 4
		var instances := MultiMesh.new()
		instances.transform_format = MultiMesh.TRANSFORM_3D
		instances.mesh = mesh_value
		rivets.multimesh = instances
		rivets.material_override = material
		rivets.set_meta("rivet_transforms", [])
		parent.add_child(rivets)
	var transforms: Array = rivets.get_meta("rivet_transforms")
	transforms.append(Transform3D(Basis(Quaternion(Vector3.UP, normal)), at))
	rivets.multimesh.instance_count = transforms.size()
	for index in transforms.size():
		rivets.multimesh.set_instance_transform(index, transforms[index])


func _build_interaction_area() -> void:
	interaction_area = Area3D.new()
	interaction_area.name = "InteractionArea"
	interaction_area.collision_layer = INTERACT_LAYER
	interaction_area.collision_mask = 0
	interaction_area.monitorable = true
	interaction_area.set_meta("interaction_owner", self)
	var focus_shape := CollisionShape3D.new()
	var focus_box := BoxShape3D.new()
	focus_box.size = Vector3(2.25, 1.8, 1.75)
	focus_shape.shape = focus_box
	focus_shape.position.y = 0.82
	interaction_area.add_child(focus_shape)
	add_child(interaction_area)


func get_interaction_prompt() -> String:
	if state == ChestState.OPENING:
		return "%s 여는 중..." % container.title
	if state == ChestState.OPENED or opened:
		if container.is_empty():
			return "[E] 빈 %s 살펴보기" % container.title
		return "[E] %s 다시 살펴보기" % container.title
	return "[E] %s 열기 · %.1f초" % [container.title, OPEN_DURATION]


func interact(player_ref: DungeonPlayer) -> void:
	if state == ChestState.OPENED or opened:
		open_requested.emit(self)
		return
	if state != ChestState.CLOSED or not is_instance_valid(player_ref):
		return
	state = ChestState.OPENING
	opening_player = player_ref
	var approach := to_local(player_ref.global_position)
	_hand_approach = ("right" if approach.x > 0.0 else "left") if absf(approach.x) > absf(approach.z) * 1.3 else ("back" if approach.z > 0.0 else "front")
	if not player_ref.begin_timed_interaction(self, OPEN_DURATION, "%s 여는 중" % container.title):
		state = ChestState.CLOSED
		opening_player = null


func complete_timed_interaction(player_ref: DungeonPlayer) -> void:
	if state != ChestState.OPENING or player_ref != opening_player:
		return
	opening_player = null
	state = ChestState.OPENED
	opened = true
	container.ever_opened = true
	_animate_open()
	open_requested.emit(self)


func cancel_timed_interaction(player_ref: DungeonPlayer) -> void:
	if state != ChestState.OPENING or player_ref != opening_player:
		return
	opening_player = null
	state = ChestState.CLOSED
	if is_instance_valid(_lid_tween):
		_lid_tween.kill()
	if is_instance_valid(lid_pivot):
		lid_pivot.rotation = _lid_closed_rotation


func set_opening_progress(value: float) -> void:
	if state != ChestState.OPENING or not is_instance_valid(lid_pivot) or not is_finite(value):
		return
	var pull := smoothstep(0.78, 0.94, clampf(value, 0.0, 1.0))
	# The imported hinge is at the rear (+Z). Positive X raises the front
	# edge; negative X would swing the lid down through the chest body.
	lid_pivot.rotation = _lid_closed_rotation + Vector3(deg_to_rad(68.0) * pull, 0.0, 0.0)


func get_hand_contact_transform(side: int, progress: float) -> Transform3D:
	# Contact points belong to the real imported wood/iron, including the lid's
	# live pivot. The frame is orthonormal despite the model's authored scale.
	var slat_name := "LidSlat00"
	var local_point := Vector3(-float(side) * 0.37, 0.064, -0.035)
	var finger_axis := Vector3.BACK
	var edge_axis := Vector3.FORWARD
	if _hand_approach == "back":
		slat_name = "LidSlat06"
		local_point = Vector3(float(side) * 0.37, 0.064, 0.035)
		finger_axis = Vector3.FORWARD
		edge_axis = Vector3.BACK
	elif _hand_approach in ["left", "right"]:
		slat_name = "LidSlat02" if side < 0 else "LidSlat04"
		var edge := 1.0 if _hand_approach == "right" else -1.0
		local_point = Vector3(edge * 0.59, 0.064, 0.0)
		finger_axis = Vector3.LEFT * edge
		edge_axis = Vector3.RIGHT * edge
	var slat := find_child(slat_name, true, false) as Node3D
	var lid_contact := global_transform.orthonormalized()
	if is_instance_valid(slat):
		# Before raising the lid, slide across the real top to its rim, then
		# wrap around the outside face. The wrist remains below the rising lip
		# instead of following an overhead palm-down pose out of the camera.
		var rim_point := local_point
		if absf(edge_axis.x) > 0.5:
			rim_point.x = edge_axis.x * 0.624
		else:
			rim_point.z = edge_axis.z * 0.074
		var grip_point := rim_point
		grip_point.y = -0.025
		var slide := smoothstep(0.66, 0.72, progress)
		var wrap := smoothstep(0.72, 0.78, progress)
		var point := local_point.lerp(rim_point, slide).lerp(grip_point, wrap)
		var top_frame := _surface_contact_transform(slat, point, Vector3.UP, finger_axis)
		var grip_frame := _surface_contact_transform(slat, point, edge_axis, Vector3.UP)
		lid_contact = top_frame.interpolate_with(grip_frame, wrap)
	if side > 0 and _hand_approach == "front" and progress < 0.78:
		var lock_plate := find_child("LockPlate", true, false) as Node3D
		if is_instance_valid(lock_plate):
			var normal := -lock_plate.global_basis.z.normalized()
			var forward := lock_plate.global_basis.y.normalized()
			var lock_contact := Transform3D(Basis(normal.cross(-forward).normalized(), normal, -forward), lock_plate.to_global(Vector3(0.025, 0.07, -0.031)))
			return lock_contact.interpolate_with(lid_contact, smoothstep(0.60, 0.78, clampf(progress, 0.0, 1.0)))
	return lid_contact


static func _surface_contact_transform(surface: Node3D, point: Vector3, normal_axis: Vector3, finger_axis: Vector3) -> Transform3D:
	# Correct surface normals retain contact under the model's nonuniform scale.
	var normal := (surface.global_basis.inverse().transposed() * normal_axis).normalized()
	var tangent := surface.global_basis * finger_axis
	var forward := (tangent - normal * tangent.dot(normal)).normalized()
	return Transform3D(Basis(normal.cross(-forward).normalized(), normal, -forward), surface.to_global(point))


func get_interaction_duration() -> float:
	return 0.0 if state == ChestState.OPENED or opened else OPEN_DURATION


func is_within_hand_reach(player_ref: Node3D) -> bool:
	if not is_instance_valid(player_ref):
		return false
	# Focus can find a distant chest, but opening requires approaching the
	# actual wood so the arms never have to stretch across several metres.
	# Already-open containers retain their immediate inspection range.
	if opened or state == ChestState.OPENED:
		return true
	var local_player := to_local(player_ref.global_position)
	var gap := Vector2(maxf(absf(local_player.x) - 0.80, 0.0), maxf(absf(local_player.z) - 0.50, 0.0))
	return gap.length() <= 1.15 and absf(local_player.y - 0.90) <= 0.65


func _animate_open() -> void:
	if lid_pivot == null:
		return
	if is_instance_valid(_lid_tween):
		_lid_tween.kill()
	_lid_tween = create_tween()
	_lid_tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_lid_tween.tween_property(lid_pivot, "rotation:x", _lid_closed_rotation.x + deg_to_rad(68.0), 0.42)


func _on_container_changed() -> void:
	if rune_material == null:
		return
	if container.is_empty():
		rune_material.emission = Color(0.055, 0.08, 0.075)
		rune_material.emission_energy_multiplier = 0.08
	else:
		rune_material.emission = Color(0.025, 0.10, 0.075)
		rune_material.emission_energy_multiplier = 0.35


func _collect_lid_parts(root: Node, output: Array[Node3D]) -> void:
	for child in root.get_children():
		if child is Node3D and (String(child.name).begins_with("LidSlat") or String(child.name).begins_with("LidBand") or String(child.name).begins_with("LidEndcap")):
			output.append(child as Node3D)
		_collect_lid_parts(child, output)


static func _transform_to_ancestor(node: Node3D, ancestor: Node3D) -> Transform3D:
	var result := Transform3D.IDENTITY
	var current := node
	while current != null and current != ancestor:
		result = current.transform * result
		current = current.get_parent() as Node3D
	return result


func _disable_imported_collisions(root: Node) -> void:
	if root is CollisionObject3D:
		(root as CollisionObject3D).collision_layer = 0
		(root as CollisionObject3D).collision_mask = 0
	if root is CollisionShape3D:
		(root as CollisionShape3D).disabled = true
	for child in root.get_children():
		_disable_imported_collisions(child)


static func _apply_material_to_prefix(root: Node, prefixes: Array, material: Material) -> void:
	if root is MeshInstance3D:
		for prefix in prefixes:
			if String(root.name).begins_with(String(prefix)):
				(root as MeshInstance3D).material_override = material
				break
	for child in root.get_children():
		_apply_material_to_prefix(child, prefixes, material)


static func _set_meshes_visible_by_prefix(root: Node, prefixes: Array, visible_value: bool) -> void:
	if root is GeometryInstance3D:
		for prefix in prefixes:
			if String(root.name).begins_with(String(prefix)):
				(root as GeometryInstance3D).visible = visible_value
				break
	for child in root.get_children():
		_set_meshes_visible_by_prefix(child, prefixes, visible_value)


static func _box(size_value: Vector3, material: StandardMaterial3D) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	var mesh_value := BoxMesh.new()
	mesh_value.size = size_value
	instance.mesh = mesh_value
	instance.material_override = material
	return instance


func _material(color_value: Color, roughness_value: float, metallic_value: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color_value
	material.roughness = roughness_value
	material.metallic = metallic_value
	return material


func _textured_material(
	color_value: Color,
	texture_value: Texture2D,
	roughness_value: float,
	metallic_value: float,
	texture_scale: float
) -> StandardMaterial3D:
	var material := _material(color_value, roughness_value, metallic_value)
	material.albedo_texture = texture_value
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	material.texture_repeat = true
	material.uv1_triplanar = true
	material.uv1_triplanar_sharpness = 32.0
	material.uv1_scale = Vector3.ONE * texture_scale
	return material
