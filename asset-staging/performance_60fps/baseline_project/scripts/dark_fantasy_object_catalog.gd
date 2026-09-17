extends RefCounted
## Audited production visual factories. Constructors never enter the scene tree,
## so gameplay _ready(), mouse capture and expedition state cannot run here.
const MANIFEST_PATH := "res://assets/art_direction/object_inventory.json"
static var _manifest: Dictionary = {}
static var _scenes: Dictionary = {}
static var _mine_template: Node3D
static var _detail_materials: Dictionary = {}


static func entries() -> Array[Dictionary]:
	if _manifest.is_empty():
		_manifest = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH)) as Dictionary
	var result: Array[Dictionary] = []
	for entry: Dictionary in _manifest.get("entries", []):
		if not bool(entry.get("excluded_by_user", false)):
			result.append(entry.duplicate(true))
	return result


static func get_entry(id: String) -> Dictionary:
	for entry: Dictionary in entries():
		if entry.id == id:
			return entry
	return {}


static func build_object(id: String, variant_index: int = 0) -> Node3D:
	var entry := get_entry(id)
	if entry.is_empty():
		push_error("Unknown production art object: " + id)
		return null
	var object: Node3D
	match str(entry.factory_type):
		"scene": object = _authored_scene(entry)
		"player": object = load("res://scripts/player_appearance.gd").create_body()
		"enemy":
			var enemy: Node3D = load("res://scripts/enemy.gd").new()
			enemy.set("display_name", "굶주린 납골당지기" if entry.keeper else "성소 감시자")
			enemy.call("_build_body")
			# The actual idle wrist settles immediately after spawn. Its immutable
			# import bind pose points the blade through the legs and is not played.
			enemy.call("_update_weapon_pose", 1.0)
			object = _take_children(enemy)
		"hands":
			var hands: Node3D = load("res://scripts/chest_hand_visuals.gd").new()
			hands.call("_ensure_built")
			object = _take_children(hands)
		"staff": object = _staff()
		"bow": object = load("res://scripts/archery_visuals.gd").create_bow()
		"arrow": object = load("res://scripts/archery_visuals.gd").create_arrow()
		"flail": object = load("res://scripts/flail_visuals.gd").create_flail()
		"flail_head": object = load("res://scripts/flail_visuals.gd").create_head()
		"flail_chain":
			var visuals: GDScript = load("res://scripts/flail_visuals.gd")
			object = visuals.create_chain()
			visuals.update_chain(object, Vector3.ZERO, Vector3(0.0, -1.4, 0.0))
		"chest", "trap":
			var script_path := "res://scripts/loot_chest.gd" if entry.factory_type == "chest" else "res://scripts/trap.gd"
			var helper: Node3D = load(script_path).new()
			helper.call("_build_visuals")
			if entry.factory_type == "trap" and variant_index % 2 == 1:
				(helper.get("spike_root") as Node3D).position.y = 0.0
			object = _take_children(helper)
		"hideout": object = _hideout(entry)
		"hideout_section": object = _hideout_section(entry)
		"game", "game_box": object = _game(entry)
		"camp": object = _camp(entry)
		"spell":
			var projectile: Node3D = load("res://scripts/magic_projectile.gd").new()
			var definition: Dictionary = load("res://scripts/spell_catalog.gd").get_spell_definition(str(entry.spell_id))
			projectile.call("configure", str(entry.spell_id), definition, null, Vector3.FORWARD)
			projectile.call("_build_visual")
			object = _take_children(projectile)
		"ghost":
			var helper: Node3D = load("res://scripts/stress_perception.gd").new()
			helper.call("_build_ghost", Vector3.ZERO)
			var material: StandardMaterial3D = helper.get("_ghost_material")
			material.albedo_color.a = 0.62
			object = _take_children(helper)
		"archery_target":
			var helper: Node = load("res://scripts/test_room.gd").new()
			helper.call("_spawn_archery_accuracy_target")
			object = _take_children(helper)
		"flail_markers":
			var helper: Node = load("res://scripts/test_room.gd").new()
			helper.call("_build_flail_station_markers")
			object = _take_selected(helper, ["FlailNearLane" if variant_index % 2 == 0 else "FlailFarLane"])
		"mine_node": object = _mine_node(entry, variant_index)
		"rock": object = _rock(int(entry.variant))
		"board": object = _board(int(entry.variant))
		"mine_water": object = _mine_water(variant_index)
	if object != null:
		object.name = id.to_pascal_case()
		object.visible = true
		_sanitize(object)
		object.set_meta("production_object_id", id)
		object.set_meta("production_source", str(entry.factory))
		object.set_meta("production_variant", variant_index)
	return object


static func _scene(path: String) -> Node3D:
	if not _scenes.has(path):
		_scenes[path] = load(path)
	return (_scenes[path] as PackedScene).instantiate() as Node3D


static func _authored_scene(entry: Dictionary) -> Node3D:
	if str(entry.id) in ["rusted_longsword", "weathered_round_shield", "iron_cage_torch"]:
		return _equipment(str(entry.id))
	var helper: Node = load("res://scripts/hideout.gd").new()
	helper.call("_build_materials")
	var result := Node3D.new()
	match str(entry.id):
		"dungeon_archway": helper.call("_add_arch", result, Vector3.ZERO, 0.0, Vector3.ONE)
		"dungeon_pillar": helper.call("_add_pillar", result, Vector3.ZERO, Vector3.ONE)
		_:
			var visual := _scene(str(entry.asset_path))
			result.add_child(visual)
			helper.call("_apply_material_recursive", visual, helper.get("floor_material"))
			if str(entry.id) == "dungeon_stairs" and ResourceLoader.exists("res://scripts/dungeon_concept_visual.gd"):
				load("res://scripts/dungeon_concept_visual.gd").call("apply_stairs", visual)
	helper.free()
	return result


static func _equipment(id: String) -> Node3D:
	var helper: Node3D = load("res://scripts/player.gd").new()
	var camera := Camera3D.new()
	helper.add_child(camera)
	helper.set("camera", camera)
	var pivot := Node3D.new()
	helper.add_child(pivot)
	helper.set("weapon_pivot", pivot)
	var iron: Material = helper.call("_textured_material", Color(0.55, 0.58, 0.58), load("res://assets/ai/materials/pitted_black_iron.png"), 0.42, 0.84, 3.2)
	var leather: Material = helper.call("_material", Color(0.16, 0.075, 0.035), 0.88, 0.05)
	var selected: Array = []
	match id:
		"rusted_longsword":
			var blade: Material = helper.call("_material", Color(0.36, 0.39, 0.40), 0.36, 0.58)
			var rust: Material = helper.call("_textured_material", Color(0.48, 0.20, 0.11), load("res://assets/ai/materials/pitted_black_iron.png"), 0.48, 0.74, 4.2)
			if helper.has_method("_build_sword_visual"):
				helper.call("_build_sword_visual", iron, blade, rust)
			else:
				# Immutable baseline projects retain the pre-refactor constructor.
				var sword := _scene("res://assets/3d/dark_fantasy/rusted_longsword.glb")
				sword.name = "RustedLongswordVisual"
				pivot.add_child(sword)
				helper.call("_apply_material_to_prefix", sword, ["PittedBlade"], blade)
				helper.call("_apply_material_to_prefix", sword, ["Fuller", "Crossguard", "Guard", "Pommel"], iron)
				helper.call("_apply_material_to_prefix", sword, ["RustBloom"], rust)
			selected = ["RustedLongswordVisual"]
		"weathered_round_shield":
			helper.call("_build_shield", iron, leather)
			(helper.get("shield_pivot") as Node3D).transform = Transform3D.IDENTITY
			selected = ["WeatheredRoundShieldVisual"]
		"iron_cage_torch":
			helper.call("_build_equipped_torch", iron)
			(helper.get("torch_pivot") as Node3D).transform = Transform3D.IDENTITY
			selected = ["IronCageTorchVisual", "Flame"]
	return _take_selected(helper, selected)


static func _decode(value: Variant, helper: Node = null) -> Variant:
	if value is Dictionary:
		if value.has("v3"):
			return Vector3(value.v3[0], value.v3[1], value.v3[2])
		if value.has("v2"):
			return Vector2(value.v2[0], value.v2[1])
		if value.has("color"):
			return Color(value.color[0], value.color[1], value.color[2], value.color[3] if value.color.size() > 3 else 1.0)
		if value.has("material") and helper != null:
			return helper.get(str(value.material))
	return value


static func _hideout(entry: Dictionary) -> Node3D:
	var helper: Node = load("res://scripts/hideout.gd").new()
	helper.call("_build_materials")
	var result := Node3D.new()
	var args: Array = []
	if not bool(entry.get("parent_last", false)):
		args.append(result)
	for value: Variant in entry.args:
		args.append(_decode(value, helper))
	if bool(entry.get("parent_last", false)):
		args.append(result)
	helper.callv(str(entry.method), args)
	helper.free()
	return result


static func _hideout_section(entry: Dictionary) -> Node3D:
	var helper: Node = load("res://scripts/hideout.gd").new()
	helper.call("_build_materials")
	var section := Node3D.new()
	helper.add_child(section)
	var regions: Dictionary = helper.get("region_nodes")
	regions[str(entry.section)] = section
	helper.call(str(entry.runtime_constructor))
	return _take_selected(helper, entry.prefixes)


static func _game(entry: Dictionary) -> Node3D:
	var helper: Node3D = load("res://scripts/game.gd").new()
	helper.call("_build_materials")
	if entry.factory_type == "game_box":
		if helper.has_method("_add_architecture_visual"):
			helper.call("_add_architecture_visual", Vector3.ZERO, _decode(entry.size), str(entry.id))
		else:
			helper.call("_add_visual_box", Vector3.ZERO, _decode(entry.size), helper.get(str(entry.material)))
	else:
		var args: Array = []
		for value: Variant in entry.args:
			args.append(_decode(value, helper))
		helper.callv(str(entry.method), args)
	return _take_children(helper)


static func _staff() -> Node3D:
	var helper: Node3D = load("res://scripts/player.gd").new()
	var pivot := Node3D.new()
	helper.add_child(pivot)
	helper.set("weapon_pivot", pivot)
	var iron: Material = helper.call("_textured_material", Color(0.55, 0.58, 0.58), load("res://assets/ai/materials/pitted_black_iron.png"), 0.42, 0.84, 3.2)
	var leather: Material = helper.call("_material", Color(0.16, 0.075, 0.035), 0.88, 0.05)
	helper.call("_build_staff_visual", iron, leather)
	var staff := helper.get("staff_visual_root") as Node3D
	staff.visible = true
	staff.transform = Transform3D.IDENTITY
	return _take_selected(helper, [str(staff.name)])


static func _camp(entry: Dictionary) -> Node3D:
	var visuals: GDScript = load("res://scripts/camp_visuals.gd")
	var camp: Node3D = visuals.create_camp()
	if entry.has("recipe"):
		visuals.set_cooking(camp, str(entry.recipe), 0.68, true)
	return _take_selected(camp, entry.selection)


static func _get_mine_template() -> Node3D:
	if not is_instance_valid(_mine_template):
		_mine_template = _scene("res://assets/3d/abandoned_mine/abandoned_mine.glb")
		load("res://scripts/cave_art_direction.gd").apply_materials(_mine_template)
	return _mine_template


static func _mine_node(entry: Dictionary, variant_index: int) -> Node3D:
	var mine := _get_mine_template()
	var names: Array = entry.variant_coverage
	var name_value := str(names[posmod(variant_index, names.size())]) if not names.is_empty() else str(entry.node_name)
	var selected := mine.find_child(name_value, true, false) as Node3D
	if selected == null:
		push_error("Production mine node missing: " + name_value)
		return null
	var result := Node3D.new()
	# Duplicate only the requested assembly. Its immutable imported mesh and
	# material resources stay shared with the dormant production template.
	result.add_child(selected.duplicate(0))
	return result


static func _mine_detail_material(wood: bool) -> Material:
	var art_direction: Script = load("res://scripts/cave_art_direction.gd")
	if not wood and art_direction.has_method("geological_material"):
		return art_direction.call("geological_material", false)
	var key := "wood" if wood else "rock"
	if _detail_materials.has(key):
		return _detail_materials[key]
	var mine := _get_mine_template()
	var visual := mine.find_child("*Mine_AgedOak" if wood else "Terrain_*", true, false) as MeshInstance3D
	var helper: Node3D = load("res://scripts/cave_art_details.gd").new()
	var material: Material = helper.call("_detail_material", visual.get_active_material(0), wood)
	helper.free()
	_detail_materials[key] = material
	return material


static func release_cached_templates() -> void:
	if is_instance_valid(_mine_template):
		_mine_template.free()
	_mine_template = null
	_detail_materials.clear()
	_scenes.clear()


static func _rock(variant: int) -> Node3D:
	var helper: Node3D = load("res://scripts/cave_art_details.gd").new()
	helper.call("_load_rock_meshes")
	var meshes: Array = helper.get("_meshes")
	var visual := MeshInstance3D.new()
	visual.mesh = meshes[variant]
	visual.material_override = _mine_detail_material(false)
	var result := Node3D.new()
	result.add_child(visual)
	helper.free()
	return result


static func _board(variant: int) -> Node3D:
	var helper: Node3D = load("res://scripts/cave_art_details.gd").new()
	var mesh: ArrayMesh = helper.call("_fragment_mesh", 500 + variant, true)
	var samples := JSON.parse_string(FileAccess.get_file_as_string("res://assets/art_direction/mine_board_samples.json")) as Dictionary
	var sample: Dictionary = samples[str(12 + variant)]
	var basis_value := Basis(_array_vector(sample.basis[0]), _array_vector(sample.basis[1]), _array_vector(sample.basis[2]))
	var batch := MultiMesh.new()
	batch.transform_format = MultiMesh.TRANSFORM_3D
	batch.use_colors = true
	batch.mesh = mesh
	batch.instance_count = 1
	batch.set_instance_transform(0, Transform3D(basis_value, _array_vector(sample.origin)))
	batch.set_instance_color(0, Color(sample.color[0],sample.color[1],sample.color[2],sample.color[3]))
	var visual := MultiMeshInstance3D.new()
	visual.multimesh = batch
	visual.material_override = _mine_detail_material(true)
	visual.set_meta("production_board_batch", sample.batch)
	var result := Node3D.new()
	result.add_child(visual)
	helper.free()
	return result


static func _array_vector(values: Array) -> Vector3:
	return Vector3(values[0], values[1], values[2])


static func _mine_water(variant: int) -> Node3D:
	var water: Node3D = load("res://scripts/cave_water.gd").new()
	var geometry: Node3D = load("res://scripts/cave_geometry.gd").new()
	geometry.call("_read_samples")
	water.call("build", geometry)
	var surfaces: Array = water.get("surfaces")
	var selected := surfaces[posmod(variant, surfaces.size())] as Node3D
	var result := Node3D.new()
	water.remove_child(selected)
	result.add_child(selected)
	water.free()
	geometry.free()
	return result


static func _take_children(helper: Node) -> Node3D:
	var result := Node3D.new()
	for child: Node in helper.get_children():
		helper.remove_child(child)
		result.add_child(child)
	helper.free()
	return result


static func _take_selected(helper: Node, prefixes: Array) -> Node3D:
	var result := Node3D.new()
	_collect_selection(helper, result, prefixes, Transform3D.IDENTITY)
	helper.free()
	return result


static func _collect_selection(node: Node, output: Node3D, prefixes: Array, parent_transform: Transform3D) -> void:
	for child: Node in node.get_children():
		var local_transform := parent_transform
		if child is Node3D:
			local_transform = parent_transform * (child as Node3D).transform
		var selected := false
		for prefix: String in prefixes:
			if str(child.name).begins_with(prefix):
				selected = true
				break
		if selected and child is Node3D:
			node.remove_child(child)
			output.add_child(child)
			(child as Node3D).transform = local_transform
			(child as Node3D).visible = true
		else:
			_collect_selection(child, output, prefixes, local_transform)


static func _sanitize(node: Node) -> void:
	# Remove callbacks before first tree entry; no actor can run gameplay logic.
	if node.get_script() != null:
		node.set_script(null)
	node.process_mode = Node.PROCESS_MODE_DISABLED
	if node is MeshInstance3D and (str(node.name).begins_with("collision_") or bool(node.get_meta("collision_only", false))):
		(node as MeshInstance3D).visible = false
	if node is GeometryInstance3D:
		(node as GeometryInstance3D).layers = 1
		(node as GeometryInstance3D).visibility_range_begin = 0.0
		(node as GeometryInstance3D).visibility_range_end = 0.0
	if node is CollisionObject3D:
		(node as CollisionObject3D).collision_layer = 0
		(node as CollisionObject3D).collision_mask = 0
	if node is Light3D:
		(node as Light3D).layers = 1
		(node as Light3D).light_cull_mask = 1
	for child: Node in node.get_children():
		if child is CollisionShape3D or child is Camera3D or child is AudioStreamPlayer3D or child is WorldEnvironment or child is CanvasLayer or child is Label3D:
			node.remove_child(child)
			child.free()
		else:
			_sanitize(child)
