extends SceneTree

const BOW := preload("res://scripts/archery_visuals.gd")
const FLAIL := preload("res://scripts/flail_visuals.gd")
const MOTION := preload("res://scripts/first_person_motion.gd")
var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var original := ExpeditionSession.capture_snapshot()
	var mouse := Input.mouse_mode
	var world := Node3D.new()
	root.add_child(world)
	var bow := BOW.create_bow()
	world.add_child(bow)
	var arrow := bow.get_node("NockedArrow") as Node3D
	for draw in [0.0, 0.1, 0.25, 0.5, 0.75, 1.0]:
		BOW.set_bow_draw(bow, draw)
		var contacts := BOW.bow_hand_anchors(bow)
		_check((contacts.grip as Vector3).is_equal_approx((bow.get_node("LeatherGrip") as Node3D).position), "Left bow hand must hold the actual wrapped grip centre")
		var nock := arrow.transform * (arrow.get_node("ArrowNock") as Node3D).position
		_check(nock.distance_to(contacts.string) < 0.00001, "Right draw fingers and the real arrow nock must share a contact at every draw ratio")
		var total_cord := 0.0
		for side in [-1, 1]:
			var segment := bow.get_node("String_%d" % side) as MeshInstance3D
			var start := segment.transform * Vector3(0, -0.5, 0)
			var finish := segment.transform * Vector3(0, 0.5, 0)
			total_cord += start.distance_to(finish)
			_check(start.distance_to(contacts.string) < 0.00001, "Both real bowstring segments must meet the draw hand and nock")
			_check(finish.distance_to((bow.get_node("Tip_%d" % side) as Node3D).position) < 0.00001, "The string must stay tied to each bending limb tip")
		_check(absf(total_cord - BOW.STRING_LENGTH) < 0.0001, "Extended draw must bend the limbs without stretching the real bowstring")
		var rest_offset: Vector3 = contacts.arrow_rest - arrow.position
		_check(rest_offset.cross(contacts.arrow_forward).length() < 0.00001 and (contacts.arrow_forward as Vector3).is_equal_approx(Vector3.FORWARD), "Arrow must rest above the grip on its unchanged forward aiming axis")
		_check(float(contacts.arrow_rest.y) > 0.09, "Nocked shaft must clear the wrapped grip instead of passing through it")
		var mesh: Mesh = (bow.get_node("SmoothBentOakLimb_1") as MeshInstance3D).mesh
		BOW.set_bow_draw(bow, draw)
		_check((bow.get_node("SmoothBentOakLimb_1") as MeshInstance3D).mesh == mesh, "Unchanged draw must reuse the submitted limb geometry")
	var full_contacts := BOW.bow_hand_anchors(bow)
	_check(is_equal_approx(float(full_contacts.string.z), BOW.STRING_DRAW_Z), "Full draw must expose the authored wide two-hand contact")
	BOW.set_bow_draw(bow, NAN)
	_check(BOW.bow_hand_anchors(bow) == full_contacts, "Invalid draw values must not corrupt hand, string or limb transforms")
	bow.position = Vector3(0.8, -0.2, 0.4)
	bow.rotation = Vector3(0.2, 1.0, -0.1)
	world.position = Vector3(-4, 2, 6)
	world.rotation.y = 0.6
	_check((bow.get_node("StringGrip") as Node3D).global_position.distance_to(bow.global_transform * (full_contacts.string as Vector3)) < 0.00001, "Contact markers must survive real viewmodel and world transforms")
	var shaft := (arrow.get_node("WoodenShaft") as MeshInstance3D).mesh as CylinderMesh
	_check(shaft.top_radius <= 0.005 and shaft.bottom_radius <= 0.005, "Arrow shaft must retain its slender physical diameter")
	_check(arrow.has_node("StringNock/NockCheek_-1") and arrow.has_node("StringNock/NockCheek_1"), "Real forked nock must leave a slot for the string")
	arrow.visible = false
	BOW.set_bow_draw(bow, 0.0)
	_check(not arrow.visible and is_equal_approx(float(BOW.bow_hand_anchors(bow).string.z), BOW.STRING_REST_Z), "Cancelling draw must restore contacts while preserving gameplay-owned arrow visibility")
	var flail := FLAIL.create_flail()
	world.add_child(flail)
	var chain := flail.get_node("Chain") as Node3D
	for at in [Vector3(0.15, -0.16, -0.62), Vector3(0.2, 0.78, -0.45), Vector3(-0.7, 0.1, -1.05)]:
		FLAIL.set_head_position(flail, at, 0.018)
		var contacts := FLAIL.flail_hand_anchors(flail)
		_check((contacts.grip as Vector3).is_equal_approx(FLAIL.HANDLE_GRIP), "Flail wrist must stay on the wrapped handle contact")
		_check((contacts.head as Vector3).is_equal_approx(at) and (chain.get_node("End") as Node3D).position.is_equal_approx(at), "Hand motion must retain the actual ball and chain endpoint")
		_check((contacts.chain_anchor as Vector3).is_equal_approx((chain.get_node("Start") as Node3D).position), "Chain must remain linked to the actual handle eyelet")
		_check(is_equal_approx(float(chain.get_meta("submitted_chain_sag")), 0.018), "Visual tension changes must use the real linked chain curve")
	var before := FLAIL.flail_hand_anchors(flail)
	FLAIL.set_head_position(flail, Vector3(NAN, 0, 0))
	_check(FLAIL.flail_hand_anchors(flail) == before, "Invalid visual pose must not dislocate the real head")
	FLAIL.set_head_visible(flail, false)
	_check(not bool(FLAIL.flail_hand_anchors(flail).head_attached) and (flail.get_node("LeatherHandle") as Node3D).visible, "Throw must hide only the held head and chain while retaining the grip")
	FLAIL.set_head_visible(flail, true)
	_check(bool(FLAIL.flail_hand_anchors(flail).head_attached), "Return must restore the original held head")
	_test_flail_head_continuity(flail)
	world.free()
	await process_frame
	_check(ExpeditionSession.capture_snapshot() == original and Input.mouse_mode == mouse, "Contact and geometry updates must preserve expedition and cursor")
	for failure in failures: push_error(failure)
	if failures.is_empty():
		print("WEAPON HAND CONTACTS PASS: real bow grip/string/nock/rest, fixed cord length, draw cache, transformed contacts, slim arrow and forked nock, flail chain/ball continuity and state isolation")
	quit(0 if failures.is_empty() else 1)


func _test_flail_head_continuity(flail: Node3D) -> void:
	var anchor: Vector3 = FLAIL.flail_hand_anchors(flail).chain_anchor
	var rest := FLAIL.flail_head_pose(anchor, "ready", 0.0, 0.0)
	_check(FLAIL.flail_head_pose(anchor, "spinning", 0.0, 0.0).distance_to(rest) < 0.000001, "Beginning the spin must not teleport the hanging ball")
	_check(FLAIL.flail_head_pose(anchor, "melee", 0.0, 0.0).distance_to(rest) < 0.000001 and FLAIL.flail_head_pose(anchor, "melee", 0.65, 0.0).distance_to(rest) < 0.000001, "Melee ball arc must begin and finish exactly at the ready position")
	var count := -1
	var links := flail.get_node("Chain/Links") as MultiMeshInstance3D
	for step in range(65):
		var angle := float(step) * TAU / 64.0
		var head := FLAIL.flail_head_pose(anchor, "spinning", 1.0, angle)
		_check(head.is_finite() and absf(head.distance_to(anchor) - FLAIL.HELD_CHAIN_LENGTH) < 0.000001, "Every point in a full flail orbit must retain the same finite chain radius")
		FLAIL.set_head_position(flail, head, 0.008)
		if count < 0: count = links.multimesh.visible_instance_count
		_check(links.multimesh.visible_instance_count == count, "A taut spin must not grow and shrink its number of chain links")
		_check((flail.get_node("Chain/End") as Node3D).position.distance_to(head) < 0.000001, "The constant-radius pose must still drive the actual chain endpoint")
		var spin_pose := MOTION.flail("spinning", 1.0, angle, 1.0)
		var in_camera: Vector3 = spin_pose * head
		var half_height := -in_camera.z * tan(deg_to_rad(76.0 / 2.0))
		_check(in_camera.z < -0.6 and absf(in_camera.y) + 0.20 < half_height and absf(in_camera.x) + 0.20 < half_height * 16.0 / 9.0, "The complete physical ball must remain in the actual camera frustum throughout a raised spin")
		var projected_grip := _project_to_view(spin_pose * FLAIL.HANDLE_GRIP)
		var nearest_chain := Geometry2D.get_closest_point_to_segment(projected_grip, _project_to_view(spin_pose * anchor), _project_to_view(in_camera))
		_check(nearest_chain.distance_to(projected_grip) > 0.11, "The spinning chain must remain visibly clear of the gripping hand rather than disappearing behind its forearm")
		for link in range(links.multimesh.visible_instance_count):
			_check(links.multimesh.get_instance_transform(link).is_finite(), "Every spinning chain link must have a finite orientation")
	var epsilon := 0.00001
	for boundary in [0.12, 0.20, 0.38, 0.65]:
		var before := FLAIL.flail_head_pose(anchor, "melee", boundary - epsilon, 0.0)
		var after := FLAIL.flail_head_pose(anchor, "melee", boundary + epsilon, 0.0)
		_check(before.distance_to(after) < 0.001, "Melee head must be continuous through windup, real impact, follow-through and recovery boundaries")
		_check(absf(after.distance_to(anchor) - FLAIL.HELD_CHAIN_LENGTH) < 0.00001, "Melee spherical arc must preserve the held chain radius")
	var first := FLAIL.flail_head_pose(anchor, "spinning", 1.0, TAU - epsilon)
	var next := FLAIL.flail_head_pose(anchor, "spinning", 1.0, epsilon)
	_check(first.distance_to(next) < 0.001, "Wrapping the orbit phase must not jump the ball")
	var impact_pose := MOTION.flail("melee", 0.20, 0.0, 0.0)
	var impact_head: Vector3 = impact_pose * FLAIL.flail_head_pose(anchor, "melee", 0.20, 0.0)
	var impact_grip: Vector3 = impact_pose * FLAIL.HANDLE_GRIP
	_check(impact_head.x < impact_grip.x - 0.25 and impact_head.z < impact_grip.z - 0.25, "Melee impact must place the ball visibly forward and left of the actual gripping hand")
	_check(FLAIL.flail_head_pose(anchor, "recovery", 0.0, 0.0).distance_to(anchor) < 0.06 and FLAIL.flail_head_pose(anchor, "recovery", 0.25, 0.0).distance_to(rest) < 0.000001, "Returning ball must settle from the catch to the same ready pose")
	_check(FLAIL.flail_head_pose(anchor, "spinning", NAN, INF).is_finite(), "Nonfinite presentation inputs must fail to a safe finite resting pose")


func _project_to_view(point: Vector3) -> Vector2:
	return Vector2(point.x, point.y) / maxf(-point.z, 0.001)


func _check(condition: bool, message: String) -> void:
	if not condition and not failures.has(message): failures.append(message)
