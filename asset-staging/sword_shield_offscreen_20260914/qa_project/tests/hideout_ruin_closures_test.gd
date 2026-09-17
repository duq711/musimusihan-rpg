extends SceneTree

const HIDEOUT := preload("res://scripts/hideout.gd")
const CLOSURES := preload("res://scripts/hideout_ruin_closures.gd")
const ROOF := preload("res://scripts/hideout_ruin_roof.gd")
const MASONRY := preload("res://scripts/hideout_ruin_masonry.gd")
var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var session_before := ExpeditionSession.capture_snapshot()
	var original_bag: ExpeditionInventory = session_before.inventory
	var original_slots: Array = original_bag.slots.duplicate(true) if original_bag != null else []
	var cursor_before := Input.mouse_mode
	# Use the production room builders off-tree; never run hideout _ready,
	# create its player, or invoke gameplay input/window initialization.
	var hideout := HIDEOUT.new()
	hideout._build_materials()
	hideout.world_root = Node3D.new()
	hideout.add_child(hideout.world_root)
	hideout.regions_root = Node3D.new()
	hideout.world_root.add_child(hideout.regions_root)
	hideout._create_regions()
	hideout._build_entry_and_stairs()
	hideout._build_workshop()
	hideout._build_drainage_tunnel()
	var preserved: Array[Dictionary] = []
	var original_nodes := _all_nodes(hideout)
	for node in original_nodes:
		if node is CollisionObject3D:
			preserved.append({"node": node, "parent": node.get_parent(), "transform": node.transform, "layer": node.collision_layer, "mask": node.collision_mask})
		elif node is CollisionShape3D:
			preserved.append({"node": node, "parent": node.get_parent(), "transform": node.transform, "shape": node.shape, "shape_state": _shape_state(node.shape)})
	_check(CLOSURES.build(hideout) == CLOSURES.PIECES.size(), "every missing entrance/gate shell closure is added to the real room hierarchy")
	_check(CLOSURES.build(hideout) == 0, "closure installation is idempotent")
	for piece: Dictionary in CLOSURES.PIECES:
		_test_piece(hideout, piece)
	var after_nodes := _all_nodes(hideout)
	for node in after_nodes:
		if not original_nodes.has(node):
			_check(not node is CollisionObject3D and not node is CollisionShape3D, "closures add only visible architecture, never new blocking physics")
	for entry in preserved:
		var node: Node3D = entry.node
		_check(node.get_parent() == entry.parent and node.transform == entry.transform, "original collision hierarchy/transform remains identical: " + str(node.name))
		if node is CollisionObject3D:
			_check(node.collision_layer == entry.layer and node.collision_mask == entry.mask, "original collision layers remain identical: " + str(node.name))
		elif node is CollisionShape3D:
			_check(node.shape == entry.shape and _shape_state(node.shape) == entry.shape_state, "original collision shape resource and dimensions remain identical: " + str(node.name))
	_check(hideout.find_child("EntranceTravelInteraction", true, false) != null and hideout.find_child("DrainGateInteraction", true, false) != null, "the actual travel and drainage interactions remain available")
	_check(ExpeditionSession.capture_snapshot() == session_before and Input.mouse_mode == cursor_before, "isolated structural construction preserves the original journey and cursor mode")
	_check(original_bag == null or original_bag.slots == original_slots, "structural construction preserves the original bag contents")
	hideout.free()
	if failures.is_empty():
		print("HIDEOUT RUIN CLOSURES PASS: real stone headers seal unintended doorway/ceiling gaps, retain intended roof apertures and room bounds, preserve original passage physics and session state")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)


func _test_piece(hideout: Node, piece: Dictionary) -> void:
	var region: Node3D = hideout.region_nodes[piece.region]
	var architecture := region.get_node("RuinClosure_" + str(piece.id)) as Node3D
	var size: Vector3 = piece.size
	var at: Vector3 = piece.position
	var box := AABB(at - size * 0.5, size)
	var bounds: AABB = region.get_meta("streaming_bounds")
	_check(bounds.grow(0.35).encloses(box), "new geometry stays inside its authored room boundary: " + str(piece.id))
	_check(box.position.y >= 3.17, "all infill is above the unchanged player passage: " + str(piece.id))
	_check(architecture.position == at and str(architecture.get_meta("architecture_kind")) == "ossuary_wall", "closure uses the production assembled stone architecture: " + str(piece.id))
	var visible := architecture.get_node("BondedMasonryBlocks") as MeshInstance3D
	_check(visible.mesh is ArrayMesh and (visible.mesh as ArrayMesh).surface_get_array_len(0) > 24 and architecture.has_node("RecessedMortarCore") and architecture.has_node("MortarBoundarySeal") and architecture.has_node("SolidArchitectureShadow"), "chipped stone faces plus sealed mortar close the visible gap: " + str(piece.id))
	_check(MASONRY.weather_geometry(architecture) == 1 and visible.mesh.has_meta("hideout_erosion_max_displacement"), "closure receives the same physical erosion pass as adjoining ruin walls: " + str(piece.id))
	var footprint := Rect2(Vector2(box.position.x, box.position.z), Vector2(box.size.x, box.size.z))
	for opening: Dictionary in ROOF.OPENINGS[piece.region]:
		var hole := Rect2(opening.xz - opening.size * 0.5, opening.size)
		_check(not footprint.intersects(hole), "closure cannot fill an intentional broken roof aperture: " + str(piece.id))
	if str(piece.id) == "EntranceArchHeader":
		_check(box.has_point(Vector3(0.0, 3.75, 20.18)) and box.position.y <= 3.21 and box.end.y >= 4.20, "entrance header bridges the real arch crown to the vestibule ceiling")
	elif str(piece.id) == "WorkshopDrainHeader":
		_check(box.has_point(Vector3(16.08, 3.95, -5.0)) and box.position.y <= 3.301 and box.end.y >= 4.15, "workshop header bridges the real drainage gate to the taller workshop ceiling")


func _all_nodes(node: Node) -> Array[Node]:
	var result: Array[Node] = [node]
	for child in node.get_children():
		result.append_array(_all_nodes(child))
	return result


func _shape_state(shape: Shape3D) -> Dictionary:
	var result := {}
	for descriptor: Dictionary in shape.get_property_list():
		if int(descriptor.usage) & PROPERTY_USAGE_STORAGE:
			result[str(descriptor.name)] = shape.get(descriptor.name)
	return result


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
