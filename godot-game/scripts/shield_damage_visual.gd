extends RefCounted

# The three stages share the exact shield transform and four grip markers.
# Only the surface mesh changes; the arm rig, poses and renderer stay intact.
const SOURCES := {
	"high": "res://assets/3d/player/sword_shield/round_shield.glb",
	"medium": "res://assets/3d/player/shield_damage/round_shield_medium.glb",
	"low": "res://assets/3d/player/shield_damage/round_shield_low.glb"
}
const MATERIALS := preload("res://scripts/sword_shield_arm_visual.gd")
static var _meshes: Dictionary = {}

static func apply(model: Node3D, stage: String) -> void:
	if not is_instance_valid(model) or not SOURCES.has(stage): return
	var surface := model.find_child("SwordsmanRoundShield_Surface", true, false) as MeshInstance3D
	if surface == null or str(model.get_meta("damage_stage", "")) == stage: return
	if not _meshes.has("high"): _meshes["high"] = surface.mesh
	if not _meshes.has(stage):
		var packed := load(SOURCES[stage]) as PackedScene
		if packed == null: return
		var sample := packed.instantiate()
		var replacement := sample.find_child("SwordsmanRoundShield_Surface", true, false) as MeshInstance3D
		if replacement != null: _meshes[stage] = replacement.mesh
		sample.free()
	if not _meshes.has(stage): return
	for index in surface.mesh.get_surface_count(): surface.set_surface_override_material(index, null)
	surface.mesh = _meshes[stage]
	MATERIALS.prepare_materials(surface)
	# New exposed end grain is rough pale wood, not the weathered outer atlas.
	for index in surface.mesh.get_surface_count():
		var source := surface.get_active_material(index) as StandardMaterial3D
		if source != null and source.resource_name.begins_with("FP_ShieldFracture"):
			var fracture := source.duplicate() as StandardMaterial3D
			fracture.vertex_color_use_as_albedo = false
			fracture.cull_mode = BaseMaterial3D.CULL_DISABLED
			surface.set_surface_override_material(index, fracture)
	model.set_meta("damage_stage", stage)
	model.set_meta("damage_source_path", SOURCES[stage])

static func snapshot(model: Node3D) -> Dictionary:
	if not is_instance_valid(model): return {}
	var surface := model.find_child("SwordsmanRoundShield_Surface", true, false) as MeshInstance3D
	if surface == null: return {}
	var vertices := 0
	for index in surface.mesh.get_surface_count(): vertices += surface.mesh.surface_get_array_len(index)
	return {"visual_stage": model.get_meta("damage_stage", "high"), "source_path": model.get_meta("damage_source_path", SOURCES.high),
		"mesh_id": surface.mesh.get_instance_id(), "node_name": str(surface.name), "vertex_count": vertices,
		"surface_count": surface.mesh.get_surface_count()}
