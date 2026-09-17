extends SceneTree
## Read the production sampler and imported blade; do not create a player,
## install a diagnostic clip, advance combat, or depend on staging being present.
const MOTION := preload("res://scripts/reference_sword_motion.gd")
const GRIP := preload("res://scripts/sword_long_grip_visual.gd")
const MODEL_PATH := "res://assets/3d/player/sword_hold_long_grip/SwordHold_Static.glb"
const MODEL_SHA256 := "2b94cc385f837fe253552cd654cb1f665246f61cdee5227814d63049da9f22fb"
# Independently measured from all 726 source blade vertices after normalization:
# X is width, Y is length, Z is thickness. The broad face is XY, normal +/-Z.
const BLADE_BOUNDS := AABB(Vector3(-0.031, -0.010, -0.0045), Vector3(0.062, 1.045, 0.009))
const BLADE_POINTS := {
	"center": Vector3(0.0, 0.5125, 0.0),
	"blade_65cm": Vector3(0.0, 0.65, 0.0),
	"tip": Vector3(0.0, 1.035, 0.0),
}
const DERIVATIVE_SECONDS := 0.001
const MIN_TRANSVERSE_SPEED := 0.01
const MAX_EDGE_ERROR_DEGREES := 5.0
const SWEEP_START := 0.675
const SWEEP_END := 0.780
const CONTACT_TIME := 0.710
const SWEEP_INTERVALS := 84
const OPTIONAL_BASELINE := "../asset-staging/sword_edge_alignment_20260913/baseline/godot-game/assets/animations/reference_sword_motion/motion_manifest.json"
var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _check(ok: bool, message: String) -> void:
	if not ok and not failures.has(message): failures.append(message)


func _run() -> void:
	var manifest_before := FileAccess.get_sha256(MOTION.MANIFEST_PATH)
	var model_before := FileAccess.get_sha256(MODEL_PATH)
	var cursor := Input.mouse_mode
	_check(model_before == MODEL_SHA256, "Edge alignment must retain the exact original SwordHold_Static GLB bytes.")
	_test_geometry()
	var available := MOTION.has_track("right_diagonal", "sword")
	_check(available and MOTION.get_load_error().is_empty(), "The production right_diagonal track must load: " + MOTION.get_load_error())
	var result := {"baseline": _test_optional_preservation()}
	if available:
		result["orientation"] = _test_orientation()
		result["sweep"] = _test_sweep()
	_check(manifest_before == FileAccess.get_sha256(MOTION.MANIFEST_PATH) and model_before == FileAccess.get_sha256(MODEL_PATH), "Sampling and geometry inspection must preserve the production manifest and original model.")
	_check(Input.mouse_mode == cursor, "Pure blade inspection must preserve mouse mode.")
	for message in failures: push_error(message)
	print("SWORD EDGE ALIGNMENT %s %s" % ["PASS" if failures.is_empty() else "FAIL", JSON.stringify(result)])
	quit(0 if failures.is_empty() else 1)


func _test_geometry() -> void:
	var sword := GRIP.create_sword()
	var blade := sword.find_child("PittedBlade", true, false) as MeshInstance3D
	_check(blade != null and blade.mesh != null, "The real normalized PittedBlade must exist.")
	if blade != null and blade.mesh != null:
		var bounds := blade.mesh.get_aabb()
		_check(blade.transform.is_equal_approx(Transform3D.IDENTITY), "The blade's canonical axes must be the actual sword pivot axes.")
		_check(bounds.position.distance_to(BLADE_BOUNDS.position) < 0.00002 and bounds.size.distance_to(BLADE_BOUNDS.size) < 0.00002, "Actual blade geometry must remain X=62mm width, Y=1045mm length, Z=9mm thickness.")
		_check(bounds.get_center().distance_to(BLADE_POINTS.center) < 0.00002, "The sweep center must match the actual normalized blade center.")
		var tip := sword.get_node_or_null("BladeTip") as Marker3D
		_check(tip != null and tip.position.distance_to(BLADE_POINTS.tip) < 0.00002, "The tested tip must match the actual blade endpoint marker.")
	sword.free()


func _test_orientation() -> Dictionary:
	var angles: Dictionary = {}
	for time: float in [0.62, CONTACT_TIME, 0.80]:
		var length_axis := MOTION.sample("right_diagonal", time).basis.y.normalized()
		var projected_angle := rad_to_deg(atan2(length_axis.y, length_axis.x))
		angles[str(time)] = projected_angle
		_check(length_axis.is_finite() and length_axis.x > 0.0 and length_axis.y > 0.0 and projected_angle < 45.0, "At authored %.3fs the blade must retain the approved shallow upper-right direction." % time)
	var first := MOTION.sample("right_diagonal", 0.62).basis.y.normalized()
	var previous := first
	var minimum_neighbor_dot := 1.0
	var minimum_start_dot := 1.0
	for index in range(181):
		var time := 0.62 + float(index) * 0.001
		var pose := MOTION.sample("right_diagonal", time)
		var length_axis := pose.basis.y.normalized()
		_check(pose.origin.is_finite() and pose.basis.is_finite() and pose.basis.get_scale().distance_to(Vector3.ONE) < 0.00001 and absf(pose.basis.determinant() - 1.0) < 0.00001, "The cutting frame must remain a finite, unscaled rotation.")
		# Signed dots are intentional: abs(dot) would silently accept a 180-degree flip.
		minimum_neighbor_dot = minf(minimum_neighbor_dot, previous.dot(length_axis))
		minimum_start_dot = minf(minimum_start_dot, first.dot(length_axis))
		previous = length_axis
	_check(minimum_neighbor_dot > 0.0 and minimum_start_dot > 0.0, "The blade length direction must not reverse during the authored .62-.80s cut.")
	return {"projected_angles_degrees": angles, "minimum_neighbor_dot": minimum_neighbor_dot, "minimum_start_dot": minimum_start_dot}


func _test_sweep() -> Dictionary:
	var report: Dictionary = {}
	for point_name: String in BLADE_POINTS:
		report[point_name] = {"moving_samples": 0, "before_contact": 0, "after_contact": 0, "max_edge_error_degrees": 0.0, "worst_authored_seconds": 0.0}
	# Central differences remain inside the authored active interval. Interior
	# source keys stay in the test: the real cubic sampler must work between them.
	for index in range(SWEEP_INTERVALS + 1):
		var time := lerpf(SWEEP_START, SWEEP_END, float(index) / SWEEP_INTERVALS)
		_record_sweep_sample(time, report)
	# Explicit exact contact also prevents an entirely stationary or axial-only
	# clip from passing by skipping every sample as numerical rest.
	var contact := _point_speeds(CONTACT_TIME)
	for point_name: String in BLADE_POINTS:
		var values: Dictionary = report[point_name]
		var hit: Dictionary = contact[point_name]
		_check(int(values.moving_samples) >= 20 and int(values.before_contact) > 0 and int(values.after_contact) > 0, point_name + ": the real sweep must contain moving samples before and after contact.")
		_check(float(hit.transverse_speed) >= MIN_TRANSVERSE_SPEED, point_name + ": exact contact must contain transverse cutting movement.")
		_check(float(hit.edge_error_degrees) <= MAX_EDGE_ERROR_DEGREES, "%s: contact must move within 5 degrees of the blade plane, measured perpendicular to its length (actual %.4f degrees)." % [point_name, float(hit.edge_error_degrees)])
		_check(float(values.max_edge_error_degrees) <= MAX_EDGE_ERROR_DEGREES, "%s: moving sweep must stay within 5 degrees of the blade plane (worst %.4f degrees at %.5fs)." % [point_name, float(values.max_edge_error_degrees), float(values.worst_authored_seconds)])
		values["contact"] = hit
	return report


func _record_sweep_sample(time: float, report: Dictionary) -> void:
	var measured := _point_speeds(time)
	for point_name: String in BLADE_POINTS:
		var sample_result: Dictionary = measured[point_name]
		if float(sample_result.transverse_speed) < MIN_TRANSVERSE_SPEED: continue
		var values: Dictionary = report[point_name]
		values.moving_samples += 1
		if time < CONTACT_TIME - DERIVATIVE_SECONDS: values.before_contact += 1
		if time > CONTACT_TIME + DERIVATIVE_SECONDS: values.after_contact += 1
		if float(sample_result.edge_error_degrees) > float(values.max_edge_error_degrees):
			values.max_edge_error_degrees = sample_result.edge_error_degrees
			values.worst_authored_seconds = time


func _point_speeds(time: float) -> Dictionary:
	var pose := MOTION.sample("right_diagonal", time)
	var before := MOTION.sample("right_diagonal", time - DERIVATIVE_SECONDS)
	var after := MOTION.sample("right_diagonal", time + DERIVATIVE_SECONDS)
	var length_axis := pose.basis.y.normalized()
	var edge_axis := pose.basis.x.normalized()
	var face_normal := pose.basis.z.normalized()
	var result: Dictionary = {}
	for point_name: String in BLADE_POINTS:
		var point: Vector3 = BLADE_POINTS[point_name]
		var velocity := (after * point - before * point) / (2.0 * DERIVATIVE_SECONDS)
		var transverse := velocity - length_axis * velocity.dot(length_axis)
		_check(velocity.is_finite() and transverse.is_finite(), "%s: sampled cutting velocity must remain finite at %.5fs." % [point_name, time])
		var face_speed := absf(transverse.dot(face_normal))
		var edge_speed := absf(transverse.dot(edge_axis))
		# 0 degrees means edge-first; 90 means broad-face-first. Removing the
		# axial sliding speed prevents it from hiding a flat slap in total speed.
		result[point_name] = {"transverse_speed": transverse.length(), "normal_speed": face_speed, "edge_error_degrees": rad_to_deg(atan2(face_speed, edge_speed))}
	return result


func _test_optional_preservation() -> String:
	var current: Variant = JSON.parse_string(FileAccess.get_file_as_string(MOTION.MANIFEST_PATH))
	_check(current is Dictionary, "The production manifest must remain readable JSON.")
	if not current is Dictionary: return "invalid_manifest"
	_check(str(current.get("source", {}).get("godot_model_sha256", "")) == MODEL_SHA256, "The authored track must identify the original sword model.")
	# Optional checkout audit: a project-only checkout still runs every geometry
	# and motion assertion above. No absolute workstation path is embedded.
	var baseline_path := ProjectSettings.globalize_path("res://").path_join(OPTIONAL_BASELINE).simplify_path()
	if not FileAccess.file_exists(baseline_path): return "not_available; geometry_and_motion_checked"
	var baseline: Variant = JSON.parse_string(FileAccess.get_file_as_string(baseline_path))
	_check(baseline is Dictionary and baseline.get("clips") is Dictionary, "An available preservation baseline must be valid JSON.")
	if not baseline is Dictionary or not baseline.get("clips") is Dictionary: return "invalid_baseline"
	var original_clips: Dictionary = baseline.clips
	var current_clips: Dictionary = current.get("clips", {})
	_check(current_clips.size() == original_clips.size(), "Edge correction must preserve the original clip set.")
	for clip_name: String in original_clips:
		if clip_name != "right_diagonal":
			_check(current_clips.get(clip_name) == original_clips[clip_name], "Edge correction must preserve the original clip exactly: " + clip_name)
	var original_cut: Dictionary = original_clips.get("right_diagonal", {})
	var current_cut: Dictionary = current_clips.get("right_diagonal", {})
	_check(current_cut.get("timing") == original_cut.get("timing") and current_cut.get("tracks", {}).get("shield") == original_cut.get("tracks", {}).get("shield"), "Correcting the sword edge must preserve authored attack timing and the shield track.")
	return "all_other_clips_and_shield_preserved"
