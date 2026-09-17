extends SceneTree

const MODELS := [
	"res://assets/3d/player/gravebound_player.glb",
	"res://assets/3d/player/hands_detailed/left_hand_detailed.glb",
	"res://assets/3d/player/hands_detailed/right_hand_detailed.glb",
]

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var report := {"models": {}, "textures": {}, "uid_cache_sha256": FileAccess.get_sha256("res://.godot/uid_cache.bin"), "loaded_models": {}}
	for model: String in MODELS:
		var imports := ConfigFile.new()
		imports.load(model + ".import")
		var imported := str(imports.get_value("remap", "path", ""))
		report.models[model] = {"imported": imported, "source_sha256": FileAccess.get_sha256(model), "compiled_sha256": FileAccess.get_sha256(imported), "dependencies": ResourceLoader.get_dependencies(model)}
		for file in DirAccess.get_files_at(model.get_base_dir()):
			if not file.begins_with(model.get_file().get_basename() + "_") or not file.ends_with(".png.import"): continue
			var path := model.get_base_dir().path_join(file.trim_suffix(".import"))
			var texture_import := ConfigFile.new()
			texture_import.load(path + ".import")
			var uid_text := str(texture_import.get_value("remap", "uid", ""))
			var uid := ResourceUID.text_to_id(uid_text)
			var registered := ResourceUID.has_id(uid)
			report.textures[path] = {"uid": uid_text, "registered": registered, "registered_path": ResourceUID.get_id_path(uid) if registered else "", "compiled": texture_import.get_value("remap", "path", ""), "import_sha256": FileAccess.get_sha256(path + ".import")}
	if OS.get_cmdline_user_args().has("--load"):
		for model: String in MODELS: report.loaded_models[model] = load(model) is PackedScene
	print("SUPPLIED IMPORT UID AUDIT: " + JSON.stringify(report))
	quit(0)
