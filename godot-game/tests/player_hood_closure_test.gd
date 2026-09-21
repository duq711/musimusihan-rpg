extends SceneTree
## The user's final direction removes the hood and all cloth wrapped around the neck.
const APPEARANCE := preload("res://scripts/player_appearance.gd")
var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var body := APPEARANCE.create_body()
	root.add_child(body)
	for retired: String in ["Gravebound_PointHood", "Gravebound_InnerNeckCowl", "Gravebound_Mantle_L", "Gravebound_Mantle_R", "Gravebound_MantleBack"]:
		if body.find_child(retired, true, false) != null:
			failures.append("Removed hood or neck cloth remains in the imported model: " + retired)
	# Absence checks must not pass on an empty or incomplete import.
	for retained: String in ["Gravebound_AnatomicalHead", "Gravebound_Eyes", "Gravebound_QuiltedTorso", "Gravebound_FP_L_Arm", "Gravebound_FP_R_Arm", "Gravebound_FP_L_Hand", "Gravebound_FP_R_Hand"]:
		var part := body.find_child(retained, true, false) as MeshInstance3D
		if part == null or part.mesh == null or part.mesh.get_surface_count() == 0:
			failures.append("Removing neck cloth must preserve the actual head, torso and limbs: " + retained)
	body.free()
	for failure in failures:
		push_error(failure)
	print("PLAYER COWL REMOVAL " + ("PASS" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)
