extends Node3D
class_name DroppedItem

const WORLD_LAYER := 2
const INTERACT_LAYER := 16
const CLOTH_TEXTURE := preload("res://assets/ai/materials/concept_charcoal_linen.png")
const MAX_REACH := 3.0
const GROUND_CLEARANCE := 0.025

var stack: Dictionary = {}
var interaction_area: Area3D
var _collecting := false


# Discards are scene-local objects. They deliberately never join expedition
# snapshots or the dungeon's randomly authored loot-container list.
static func spawn_discarded(parent: Node, actor: DungeonPlayer, discarded: Dictionary) -> DroppedItem:
	if not is_instance_valid(actor) or not actor.is_inside_tree():
		return null
	var placement := find_safe_placement(actor)
	if placement.is_empty():
		restore_discard(actor.inventory_model, discarded)
		return null
	# Loading by path also works in fresh headless checkouts before Godot has
	# cached this newly added global class name.
	var item := load("res://scripts/dropped_item.gd").new() as DroppedItem
	item.name = "DroppedItem"
	item.configure(discarded)
	parent.add_child(item)
	item.global_position = placement.position
	var ground_up: Vector3 = placement.normal
	var across := actor.global_basis.x.slide(ground_up).normalized()
	item.global_basis = Basis(across, ground_up, across.cross(ground_up)).orthonormalized()
	return item


static func find_safe_placement(actor: DungeonPlayer) -> Dictionary:
	if not is_instance_valid(actor) or not actor.is_inside_tree():
		return {}
	var space := actor.get_world_3d().direct_space_state
	var forward := -actor.global_basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var right := forward.cross(Vector3.UP).normalized()
	var offsets: Array[Vector3] = []
	for distance in [1.15, 0.8, 0.45]:
		for lateral in [0.0, 0.45, -0.45]:
			offsets.append(forward * distance + right * lateral)
	offsets.append(Vector3.ZERO)
	for offset in offsets:
		var candidate := actor.global_position + offset
		# Trace at knee height so close walls and low obstacles cannot place
		# a package on their far side. Keep the whole package before a wall.
		if offset.length() > 0.001:
			var from := actor.global_position - Vector3.UP * 0.45
			var wall_query := PhysicsRayQueryParameters3D.create(from, candidate - Vector3.UP * 0.45, WORLD_LAYER)
			var wall := space.intersect_ray(wall_query)
			if not wall.is_empty():
				var clear_distance := maxf(0.0, from.distance_to(wall.position) - 0.30)
				candidate = actor.global_position + offset.normalized() * clear_distance
		var floor_query := PhysicsRayQueryParameters3D.create(candidate + Vector3.UP * 0.4, candidate - Vector3.UP * 2.3, WORLD_LAYER)
		var floor_hit := space.intersect_ray(floor_query)
		if floor_hit.is_empty() or (floor_hit.normal as Vector3).dot(Vector3.UP) < 0.7:
			continue
		var floor_at: Vector3 = floor_hit.position
		# Reject ledges above the player's waist and positions without enough
		# free volume for the small cloth package.
		if floor_at.y > actor.global_position.y - 0.35:
			continue
		var clearance := PhysicsShapeQueryParameters3D.new()
		var shape := SphereShape3D.new()
		shape.radius = 0.235
		clearance.shape = shape
		clearance.transform = Transform3D(Basis.IDENTITY, floor_at + Vector3.UP * 0.27)
		clearance.collision_mask = WORLD_LAYER
		clearance.collide_with_areas = false
		if not space.intersect_shape(clearance, 1).is_empty():
			continue
		return {"position": floor_at + Vector3.UP * GROUND_CLEARANCE, "normal": floor_hit.normal}
	return {}


static func restore_discard(model: ExpeditionInventory, discarded: Dictionary) -> void:
	if model == null or discarded.is_empty():
		return
	var slot_name := str(discarded.get("equipment_slot", ""))
	if str(discarded.get("source", "inventory")) == "equipment" and model.equipment.has(slot_name):
		model.equipment[slot_name] = str(discarded.get("id", ""))
		model.equipment_data[slot_name] = (discarded.get("instance", {}) as Dictionary).duplicate(true)
	else:
		var index := clampi(int(discarded.get("source_index", model.slots.size())), 0, model.slots.size())
		if int(discarded.get("source_remaining", 0)) > 0 and index < model.slots.size() and str(model.slots[index].get("id", "")) == str(discarded.get("id", "")) and model.slots[index].get("instance", {}) == discarded.get("instance", {}):
			model.slots[index]["quantity"] = int(model.slots[index].get("quantity", 0)) + int(discarded.get("quantity", 0))
		else:
			var restored := {"id": str(discarded.get("id", "")), "quantity": int(discarded.get("quantity", 0))}
			if discarded.has("instance"):
				restored["instance"] = (discarded.instance as Dictionary).duplicate(true)
			model.slots.insert(index, restored)
	model.changed.emit()


func configure(discarded: Dictionary) -> DroppedItem:
	stack = {"id": str(discarded.get("id", "")), "quantity": int(discarded.get("quantity", 0))}
	if discarded.has("instance"):
		stack["instance"] = (discarded.instance as Dictionary).duplicate(true)
	return self


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	add_to_group("dropped_item")
	_build_package()
	interaction_area = Area3D.new()
	interaction_area.name = "PickupArea"
	interaction_area.collision_layer = INTERACT_LAYER
	interaction_area.collision_mask = 0
	interaction_area.monitoring = false
	interaction_area.set_meta("interaction_owner", self)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.55, 0.46, 0.50)
	collision.shape = shape
	collision.position.y = 0.23
	interaction_area.add_child(collision)
	add_child(interaction_area)


func _build_package() -> void:
	var cloth := StandardMaterial3D.new()
	cloth.albedo_texture = CLOTH_TEXTURE
	cloth.albedo_color = Color(0.63, 0.56, 0.43)
	cloth.roughness = 1.0
	var bundle := MeshInstance3D.new()
	bundle.name = "ClothPackage"
	var mesh := SphereMesh.new()
	mesh.radius = 0.225
	mesh.height = 0.30
	mesh.radial_segments = 16
	mesh.rings = 8
	bundle.mesh = mesh
	bundle.material_override = cloth
	bundle.position.y = 0.15
	bundle.scale.z = 0.84
	add_child(bundle)
	var tie := MeshInstance3D.new()
	tie.name = "PackageTie"
	var knot := TorusMesh.new()
	knot.inner_radius = 0.032
	knot.outer_radius = 0.055
	knot.rings = 12
	knot.ring_segments = 6
	tie.mesh = knot
	var cord := StandardMaterial3D.new()
	cord.albedo_color = Color(0.40, 0.29, 0.16)
	cord.roughness = 1.0
	tie.material_override = cord
	tie.position.y = 0.285
	add_child(tie)


func get_interaction_prompt() -> String:
	var label := ExpeditionInventory.get_item_name(str(stack.get("id", "")))
	var tag := str((stack.get("instance", {}) as Dictionary).get("item_tag", ""))
	if not tag.is_empty():
		label += " · " + tag
	return "[E] %s ×%d 줍기" % [label, int(stack.get("quantity", 0))]


func interact(actor: Node) -> Dictionary:
	if _collecting or is_queued_for_deletion() or not actor is DungeonPlayer or get_tree().paused:
		return {"accepted": false, "reason": "unavailable"}
	var player := actor as DungeonPlayer
	var inventory := player.inventory_model
	if inventory == null or not is_instance_valid(player.camera):
		return {"accepted": false, "reason": "unavailable"}
	var target := global_position + Vector3.UP * 0.20
	var from := player.camera.global_position
	if from.distance_to(target) > MAX_REACH:
		return {"accepted": false, "reason": "out_of_reach"}
	var obstruction := PhysicsRayQueryParameters3D.create(from, target, WORLD_LAYER)
	if not get_world_3d().direct_space_state.intersect_ray(obstruction).is_empty():
		return {"accepted": false, "reason": "blocked"}
	_collecting = true
	var quantity := int(stack.get("quantity", 0))
	var remaining := inventory.add_item(str(stack.get("id", "")), quantity, true, stack.get("instance", {}))
	var moved := quantity - remaining
	stack["quantity"] = remaining
	var message := "가방이 가득 찼습니다."
	if moved > 0:
		message = "%s %d개를 주웠습니다." % [ExpeditionInventory.get_item_name(str(stack.get("id", ""))), moved]
		if remaining > 0:
			message += " 바닥에 %d개가 남았습니다." % remaining
	if is_instance_valid(player.hud):
		player.hud.show_event(message, 1.6)
		player.hud.set_prompt("")
	if remaining <= 0:
		interaction_area.collision_layer = 0
		queue_free()
	else:
		_collecting = false
	return {"accepted": moved > 0, "moved": moved, "remaining": remaining, "message": message}
