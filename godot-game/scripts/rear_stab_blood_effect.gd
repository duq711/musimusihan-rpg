extends "res://scripts/creep_wound_effect.gd"
## A small physical spray at the real rear-stab contact. Reuse the existing
## wound material/collision path; no screen overlay, emission or damage.
const BURST_LIFETIME := 6.0
const BURST_MAX_STAINS := 8
const STAIN_SCALE := .60
var _source_origin := Vector3.ZERO
var _outward_direction := Vector3.FORWARD
var _source_region := ""
var _spawned_droplets := 0


func configure(origin: Vector3, direction: Vector3, region: String) -> void:
	if _configured:
		return
	_source_origin = origin
	_outward_direction = direction.normalized() if direction.is_finite() and direction.length_squared() > .000001 else Vector3.FORWARD
	_source_region = region
	super.configure(origin, _outward_direction, region)
	# Preserve the wound's dark, non-emissive palette while giving these small
	# near-camera droplets enough diffuse response to remain visible.
	_material.albedo_color = Color(.21, .007, .011)
	_material.roughness = .43
	var lateral := _outward_direction.cross(Vector3.UP).normalized()
	if lateral.length_squared() < .000001:
		lateral = _outward_direction.cross(Vector3.RIGHT).normalized()
	var rise := lateral.cross(_outward_direction).normalized()
	for index in droplets.size():
		var drop: Dictionary = droplets[index]
		var display: MeshInstance3D = drop.mesh
		# Alternating lateral lanes keep the complete burst from sitting behind
		# the fist. Upward scatter stays modest; gravity supplies the falling arc.
		var side := -1.0 if index % 2 == 0 else 1.0
		var velocity := _outward_direction * _rng.randf_range(.65, 1.25)
		velocity += lateral * side * _rng.randf_range(.35, .95)
		velocity += rise * _rng.randf_range(.25, 1.30)
		display.position = _outward_direction * .016 + lateral * _rng.randf_range(-.012, .012) + rise * _rng.randf_range(-.004, .018)
		display.scale = Vector3.ONE * _rng.randf_range(.70, 1.40)
		display.quaternion = Quaternion(Vector3.UP, velocity.normalized())
		drop.velocity = velocity
		drop.remaining = _rng.randf_range(.85, 1.20)
	_spawned_droplets = droplets.size()


func _physics_process(delta: float) -> void:
	if not _configured or delta <= 0.0:
		return
	# Parent motion uses physics delta, world collision, and removes each drop
	# on first contact. This shorter lifetime also bounds all resulting stains.
	super._physics_process(delta)
	if age >= BURST_LIFETIME:
		queue_free()
		return
	for drop: Dictionary in droplets:
		var display: MeshInstance3D = drop.mesh
		var velocity: Vector3 = drop.velocity
		if velocity.length_squared() > .000001:
			display.quaternion = Quaternion(Vector3.UP, velocity.normalized())
	var fade := clampf((BURST_LIFETIME - age) / 1.25, .001, 1.0)
	for stain: MeshInstance3D in stains:
		stain.scale = Vector3.ONE * STAIN_SCALE * fade


func _add_stain(point: Vector3, normal: Vector3) -> void:
	# Small floor marks only: wall contact still consumes a droplet, without
	# producing an oversized surface sheet beside the victim or camera.
	if stains.size() >= BURST_MAX_STAINS or normal.dot(Vector3.UP) < .45:
		return
	super._add_stain(point, normal)
	var stain: MeshInstance3D = stains.back()
	stain.scale = Vector3.ONE * STAIN_SCALE


func snapshot() -> Dictionary:
	var positions: Array[Vector3] = []
	var velocities: Array[Vector3] = []
	var visible_droplets := 0
	for drop: Dictionary in droplets:
		var display: MeshInstance3D = drop.mesh
		positions.append(display.global_position)
		velocities.append(drop.velocity)
		if display.is_visible_in_tree():
			visible_droplets += 1
	return {
		"configured": _configured,
		"age": age,
		"lifetime_seconds": BURST_LIFETIME,
		"origin": _source_origin,
		"direction": _outward_direction,
		"region": _source_region,
		"spawned_droplet_count": _spawned_droplets,
		"live_droplets": droplets.size(),
		"visible_droplets": visible_droplets,
		"droplet_positions": positions,
		"droplet_velocities": velocities,
		"stain_count": stains.size(),
		"max_stains": BURST_MAX_STAINS,
		"top_level": is_set_as_top_level(),
		"pausable": process_mode == Node.PROCESS_MODE_PAUSABLE,
		"emission_enabled": _material.emission_enabled if _material != null else false,
		"queued_for_deletion": is_queued_for_deletion(),
	}
