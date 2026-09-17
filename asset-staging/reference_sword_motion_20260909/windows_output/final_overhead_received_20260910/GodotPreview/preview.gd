extends Node3D
## Preserve the imported GLB hierarchy, skin and bind transforms as one camera child.
## No SOURCE_READY, camera-axis or arm-part transforms are applied again here.

const MODEL_PATH := "res://assets/Overhead_Final.glb"
const EXPECTED_DURATION := 1.55

var camera: Camera3D
var model: Node3D
var player: AnimationPlayer
var clip: StringName
var status_label: Label
var sword: Node3D
var sleeve_skeleton: Skeleton3D
var initial_sword_position := Vector3.ZERO
var initial_bone_pose := Transform3D.IDENTITY
var elapsed_seconds := 0.0
var process_frames := 0
var maximum_sword_movement := 0.0
var maximum_bone_pose_change := 0.0
var verification_mode := false
var report_path := ""
var skin_meshes := 0
var mesh_count := 0
var finish_report_written := false


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	verification_mode = args.has("--verify-preview")
	var report_index := args.find("--report")
	if report_index >= 0 and report_index + 1 < args.size():
		report_path = args[report_index + 1]
	_build_view()
	_build_ui()
	if not FileAccess.file_exists(MODEL_PATH):
		_fail("Missing assets/Overhead_Final.glb")
		return
	var packed := load(MODEL_PATH) as PackedScene
	if packed == null:
		_fail("Could not import Overhead_Final.glb")
		return
	model = packed.instantiate() as Node3D
	if model == null:
		_fail("The imported GLB has no 3D root")
		return
	camera.add_child(model)
	# The root's imported axis conversion is part of the authored GLB.
	# Keep model.transform and every descendant transform unchanged.
	_inspect(model)
	if player == null:
		_fail("AnimationPlayer was not found in the full GLB")
		return
	for name: StringName in player.get_animation_list():
		if str(name).get_file().to_lower() == "overhead":
			clip = name
			break
	if clip.is_empty():
		_fail("The overhead animation was not found")
		return
	var animation := player.get_animation(clip)
	if absf(animation.length - EXPECTED_DURATION) > 0.00001 or animation.loop_mode != Animation.LOOP_NONE:
		_fail("Expected one non-looping 1.55-second overhead")
		return
	if sword == null or sleeve_skeleton == null or skin_meshes != 3 or sleeve_skeleton.get_bone_count() != 7:
		_fail("Expected the complete sword and seven-bone continuous sleeve")
		return
	player.animation_finished.connect(_on_animation_finished)
	_restart()


func _build_view() -> void:
	camera = Camera3D.new()
	camera.name = "FirstPersonCamera"
	camera.transform = Transform3D.IDENTITY
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.fov = 76.0
	camera.near = 0.025
	camera.far = 50.0
	camera.current = true
	add_child(camera)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.055, 0.07, 0.09)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.65, 0.7, 0.78)
	environment.ambient_light_energy = 0.55
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.32, 0.35, 0.4)
	sky_material.sky_horizon_color = Color(0.57, 0.59, 0.61)
	sky_material.ground_bottom_color = Color(0.055, 0.06, 0.065)
	sky_material.ground_horizon_color = Color(0.24, 0.26, 0.28)
	var reflection_sky := Sky.new()
	reflection_sky.sky_material = sky_material
	environment.sky = reflection_sky
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	var world := WorldEnvironment.new()
	world.name = "NeutralStudio"
	world.environment = environment
	add_child(world)
	var key := DirectionalLight3D.new()
	key.name = "KeyLight"
	key.rotation_degrees = Vector3(-35, -30, 0)
	key.light_color = Color(1.0, 0.94, 0.86)
	key.light_energy = 1.6
	add_child(key)
	var fill := DirectionalLight3D.new()
	fill.name = "FillLight"
	fill.rotation_degrees = Vector3(-15, 110, 0)
	fill.light_color = Color(0.69, 0.8, 1.0)
	fill.light_energy = 0.8
	add_child(fill)


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := VBoxContainer.new()
	panel.position = Vector2(24, 20)
	panel.add_theme_constant_override("separation", 8)
	layer.add_child(panel)
	var title := Label.new()
	title.text = "OVERHEAD  /  1.55 s"
	title.add_theme_font_size_override("font_size", 22)
	panel.add_child(title)
	status_label = Label.new()
	status_label.text = "Loading..."
	status_label.add_theme_color_override("font_color", Color(0.75, 0.8, 0.87))
	panel.add_child(status_label)
	var replay := Button.new()
	replay.text = "Replay  [Space]"
	replay.focus_mode = Control.FOCUS_NONE
	replay.pressed.connect(_restart)
	panel.add_child(replay)


func _inspect(node: Node) -> void:
	if node is AnimationPlayer:
		player = node
	if node is Skeleton3D:
		sleeve_skeleton = node
	if node is MeshInstance3D:
		mesh_count += 1
		if node.skin != null:
			skin_meshes += 1
	if node is Node3D and str(node.name) == "SwordGrip":
		sword = node
	for child: Node in node.get_children():
		_inspect(child)


func _restart() -> void:
	if player == null or clip.is_empty():
		return
	elapsed_seconds = 0.0
	process_frames = 0
	maximum_sword_movement = 0.0
	maximum_bone_pose_change = 0.0
	player.stop()
	player.speed_scale = 1.0
	player.play(clip, 0.0, 1.0)
	player.seek(0.0, true)
	player.advance(0.0)
	initial_sword_position = sword.global_position
	initial_bone_pose = sleeve_skeleton.get_bone_global_pose(0)
	status_label.text = "Playing at original speed"


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE:
		_restart()
		get_viewport().set_input_as_handled()


func _matrix_difference(a: Transform3D, b: Transform3D) -> float:
	var difference := a.origin.distance_to(b.origin)
	for column in range(3):
		for row in range(3):
			difference = maxf(difference, absf(a.basis[column][row] - b.basis[column][row]))
	return difference


func _process(delta: float) -> void:
	if player == null or sword == null or sleeve_skeleton == null:
		return
	if player.is_playing():
		elapsed_seconds += delta
		process_frames += 1
		maximum_sword_movement = maxf(maximum_sword_movement, sword.global_position.distance_to(initial_sword_position))
		maximum_bone_pose_change = maxf(maximum_bone_pose_change, _matrix_difference(initial_bone_pose, sleeve_skeleton.get_bone_global_pose(0)))
	if verification_mode and elapsed_seconds > 5.0 and not finish_report_written:
		_fail("Timed out waiting for the one-shot animation to finish")


func _on_animation_finished(name: StringName) -> void:
	if name != clip:
		return
	status_label.text = "Finished — press Space to replay"
	if verification_mode:
		var passed := maximum_sword_movement > 0.05 and maximum_bone_pose_change > 0.01 and process_frames > 1
		_write_report(passed, "" if passed else "Animation finished without enough evaluated motion")
		get_tree().quit(0 if passed else 1)


func _fail(message: String) -> void:
	status_label.text = message
	push_error(message)
	if verification_mode:
		_write_report(false, message)
		get_tree().quit(1)


func _write_report(passed: bool, error: String) -> void:
	if finish_report_written:
		return
	finish_report_written = true
	var result := {
		"status": "pass" if passed else "fail", "error": error,
		"godot_version": Engine.get_version_info(), "execution_os": OS.get_name(),
		"model_sha256": FileAccess.get_sha256(MODEL_PATH),
		"model_path": MODEL_PATH, "camera_identity": camera.transform.is_equal_approx(Transform3D.IDENTITY),
		"vertical_fov_degrees": camera.fov, "near_m": camera.near, "keep_aspect": camera.keep_aspect,
		"animation": str(clip), "duration_seconds": player.get_animation(clip).length if player != null and not clip.is_empty() else 0.0,
		"speed_scale": player.speed_scale if player != null else 0.0, "finished_signal_received": passed,
		"process_frames_during_playback": process_frames, "elapsed_process_seconds": elapsed_seconds,
		"maximum_sword_position_change_m": maximum_sword_movement, "maximum_skeleton_bone_pose_change": maximum_bone_pose_change,
		"mesh_instances": mesh_count, "skinned_mesh_instances": skin_meshes,
		"bone_count": sleeve_skeleton.get_bone_count() if sleeve_skeleton != null else 0,
		"hierarchy": "Full imported GLB is one child of an identity Camera3D; no extra arm or SOURCE_READY transforms applied",
		"scope": "Standalone packed-scene import and one complete original-speed playback; existing game project untouched",
		"limitations": "Headless startup verification does not claim a GPU-rendered visual comparison or Mac production integration"
	}
	if not report_path.is_empty():
		var file := FileAccess.open(report_path, FileAccess.WRITE)
		if file:
			file.store_string(JSON.stringify(result, "  ", true, true) + "\n")
			file.close()
	print("GODOT_PREVIEW_PLAYBACK " + JSON.stringify(result))
