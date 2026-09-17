extends "res://scripts/test_room.gd"

# Keep the production menu/player/HUD lifecycle; location rendering is
# independently benchmarked with complete geometry in performance_preview.gd.
func _build_dungeon() -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 2
	body.position = Vector3(0, -0.5, 0)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(28, 1, 34)
	collision.shape = shape
	body.add_child(collision)
	add_child(body)
func _spawn_encounters() -> void:
	pass
func _spawn_loot_chests() -> void:
	pass
func _build_extraction_gate() -> void:
	pass

