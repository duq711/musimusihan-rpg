extends SceneTree

const MODELS := [
	"res://assets/3d/player/gravebound_player.glb",
	"res://assets/3d/player/hands_detailed/left_hand_detailed.glb",
	"res://assets/3d/player/hands_detailed/right_hand_detailed.glb",
]

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var missing := {}
	var problems: Array[String] = []
	for model: String in MODELS:
		for dependency: String in ResourceLoader.get_dependencies(model):
			var parts := dependency.split("::::")
			if parts.size() != 2:
				problems.append("Unexpected dependency format: " + dependency)
				continue
			var path := str(parts[1])
			var uid_text := str(parts[0])
			var uid := ResourceUID.text_to_id(uid_text)
			var valid_path := path.begins_with(model.get_base_dir().path_join(model.get_file().get_basename() + "_")) and path.ends_with(".png")
			var imports := ConfigFile.new()
			if not valid_path or uid < 0 or not FileAccess.file_exists(path) or imports.load(path + ".import") != OK or str(imports.get_value("remap", "uid", "")) != uid_text:
				problems.append("Dependency does not match its existing texture import: " + dependency)
				continue
			if ResourceUID.has_id(uid):
				if ResourceUID.get_id_path(uid) != path: problems.append("Conflicting existing UID registration: " + dependency)
			else:
				missing[uid] = path
	var repair := OS.get_cmdline_user_args().has("--repair")
	var report := {"repair_requested": repair, "missing_count": missing.size(), "missing": missing, "problems": problems, "cache_update_supported": ResourceUID.has_method("update_cache")}
	if repair and problems.is_empty() and not missing.is_empty():
		if not ResourceUID.has_method("update_cache"):
			problems.append("ResourceUID.update_cache is unavailable")
		else:
			var backup_path := ProjectSettings.globalize_path("res://../asset-staging/player_supplied_hands_20260911/audit/uid_cache_before_registration.bin")
			if FileAccess.file_exists(backup_path):
				problems.append("Refusing to replace an existing UID-cache backup")
			else:
				var backup := FileAccess.open(backup_path, FileAccess.WRITE)
				if backup == null:
					problems.append("Could not preserve the previous UID cache")
				else:
					backup.store_buffer(FileAccess.get_file_as_bytes("res://.godot/uid_cache.bin"))
					backup.close()
					for uid: int in missing: ResourceUID.add_id(uid, str(missing[uid]))
					report.cache_update_result = ResourceUID.call("update_cache")
					report.backup = backup_path
					for uid: int in missing:
						if not ResourceUID.has_id(uid) or ResourceUID.get_id_path(uid) != missing[uid]: problems.append("Registration did not persist in memory")
	report.problems = problems
	report.uid_cache_sha256 = FileAccess.get_sha256("res://.godot/uid_cache.bin")
	print("SUPPLIED TEXTURE UID REGISTRATION: " + JSON.stringify(report))
	quit(0 if problems.is_empty() else 1)
