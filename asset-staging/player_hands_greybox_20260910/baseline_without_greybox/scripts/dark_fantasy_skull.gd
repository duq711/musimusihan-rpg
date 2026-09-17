extends RefCounted
class_name DarkFantasySkull

const SOURCE_PATH := "res://assets/3d/dark_fantasy/anatomical_skeleton_cc_by_4.glb"
const BAKED_MESH: ArrayMesh = preload("res://assets/3d/dark_fantasy/generated_lods/anatomical_skull_lod.res")
const SURFACES := preload("res://scripts/dark_fantasy_materials.gd")
static var _normalized_mesh: ArrayMesh
static var _source_bounds := AABB()
static var _source_piece_count := 0


static func create(height_value := 0.34, tint := Color(0.54, 0.50, 0.40)) -> MeshInstance3D:
	_prepare_mesh()
	var skull := MeshInstance3D.new()
	skull.name = "AnatomicalSkull"
	skull.mesh = _normalized_mesh
	skull.scale = Vector3.ONE * height_value
	var value := tint.get_luminance()
	skull.material_override = SURFACES.bone(Color(value * 0.97, value, value * 1.05), 4.0)
	skull.set_meta("anatomical_source", "BodyParts3D / CC BY 4.0")
	skull.set_meta("anatomical_source_pieces", _source_piece_count)
	return skull


static func source_bounds() -> AABB:
	_prepare_mesh()
	return _source_bounds


static func _prepare_mesh() -> void:
	if _normalized_mesh != null:
		return
	# The packed close-view buffers are unchanged; only distance LOD indices
	# were added offline. Every skull shares this resource without rebuilding
	# or simplifying the original anatomical skeleton during scene entry.
	_normalized_mesh = BAKED_MESH
	_source_bounds = BAKED_MESH.get_meta("source_bounds")
	_source_piece_count = int(BAKED_MESH.get_meta("source_piece_count"))


static func source_mesh_data() -> Dictionary:
	# Explicit offline regeneration and independent regression verification.
	# Production creation never loads or assembles this dense source scene.
	var source_root := (load(SOURCE_PATH) as PackedScene).instantiate() as Node3D
	var meshes: Array[MeshInstance3D] = []
	var source_box := AABB()
	for child in source_root.find_children("*", "MeshInstance3D", true, false):
		var piece := child as MeshInstance3D
		var bounds := piece.get_aabb()
		# The source GLB is a baked, metre-scale anatomical skeleton. Its
		# cranial bones and mandible lie above the atlas/axis vertebrae.
		if bounds.end.y > 1.49 and bounds.position.y > 1.415:
			meshes.append(piece)
			source_box = bounds if meshes.size() == 1 else source_box.merge(bounds)
	assert(not meshes.is_empty(), "Anatomical source must provide cranial bones")
	var surface := SurfaceTool.new()
	var normalizer := Basis(Vector3.UP, PI).scaled(Vector3.ONE / source_box.size.y)
	var transform_value := Transform3D(normalizer, -(normalizer * source_box.get_center()))
	for piece in meshes:
		for surface_index in piece.mesh.get_surface_count():
			surface.append_from(piece.mesh, surface_index, transform_value)
	var result := {"mesh": surface.commit(), "source_bounds": source_box, "source_piece_count": meshes.size()}
	source_root.free()
	return result
