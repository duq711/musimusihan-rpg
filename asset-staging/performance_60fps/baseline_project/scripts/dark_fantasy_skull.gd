extends RefCounted
class_name DarkFantasySkull

const SOURCE := preload("res://assets/3d/dark_fantasy/anatomical_skeleton_cc_by_4.glb")
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
	var source_root := SOURCE.instantiate() as Node3D
	var meshes: Array[MeshInstance3D] = []
	for child in source_root.find_children("*", "MeshInstance3D", true, false):
		var piece := child as MeshInstance3D
		var bounds := piece.get_aabb()
		# The source GLB is a baked, metre-scale anatomical skeleton. Its
		# cranial bones and mandible lie above the atlas/axis vertebrae.
		if bounds.end.y > 1.49 and bounds.position.y > 1.415:
			meshes.append(piece)
			_source_bounds = bounds if meshes.size() == 1 else _source_bounds.merge(bounds)
	assert(not meshes.is_empty(), "Anatomical source must provide cranial bones")
	var surface := SurfaceTool.new()
	var normalizer := Basis(Vector3.UP, PI).scaled(Vector3.ONE / _source_bounds.size.y)
	var transform_value := Transform3D(normalizer, -(normalizer * _source_bounds.get_center()))
	for piece in meshes:
		for surface_index in piece.mesh.get_surface_count():
			surface.append_from(piece.mesh, surface_index, transform_value)
	_source_piece_count = meshes.size()
	_normalized_mesh = surface.commit()
	source_root.free()
