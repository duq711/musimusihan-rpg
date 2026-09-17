extends RefCounted
## Hash rendering inputs once per snapshot. Large authored meshes are separately
## memoized by the gallery renderer instead of being re-read for every family.


static func collect() -> Dictionary:
	var hashes := {}
	for folder in ["res://scripts", "res://shaders"]:
		for file in DirAccess.get_files_at(folder):
			if file.ends_with(".gd") or file.ends_with(".gdshader"):
				_add(hashes, folder.path_join(file))
	for file in ["res://assets/cave_water.gdshader", "res://assets/cave_rock.gdshader", "res://assets/3d/abandoned_mine/mine_water.gdshader"]:
		_add(hashes, file)
	for file in DirAccess.get_files_at("res://assets/ai/materials"):
		if file.begins_with("concept_") and (file.ends_with(".png") or file.ends_with(".png.import")):
			_add(hashes, "res://assets/ai/materials/" + file)
	for file in ["res://assets/art_direction/object_inventory.json", "res://assets/art_direction/mine_board_samples.json", "res://tests/dark_fantasy_gallery_preview.gd", "res://tests/dark_fantasy_scene_preview.gd", "res://tests/dark_fantasy_capture_evidence.gd"]:
		_add(hashes, file)
	return hashes


static func _add(hashes: Dictionary, path: String) -> void:
	if FileAccess.file_exists(path):
		hashes[path] = FileAccess.get_sha256(path)
