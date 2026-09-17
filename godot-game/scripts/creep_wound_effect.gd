extends Node3D
## A bounded cut burst and contact stains. All motion uses pausable physics
## delta; there is no TIME shader, audio, input capture or gameplay damage.
const LIFETIME := 18.0
const DROPLET_COUNT := 24
const MAX_STAINS := 12
var age := 0.0
var droplets: Array[Dictionary] = []
var stains: Array[MeshInstance3D] = []
var _rng := RandomNumberGenerator.new()
var _material: StandardMaterial3D
var _configured := false

func configure(origin: Vector3, direction: Vector3, region: String) -> void:
	if _configured: return
	_configured = true
	process_mode = Node.PROCESS_MODE_PAUSABLE
	set_as_top_level(true)
	global_position = origin
	_rng.seed = region.hash()
	_material = StandardMaterial3D.new()
	_material.albedo_color = Color(.16, .006, .009)
	_material.roughness = .46
	_material.metallic_specular = .25
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var mesh := SphereMesh.new()
	mesh.radius = .007
	mesh.height = .024
	mesh.radial_segments = 6
	mesh.rings = 3
	for index in DROPLET_COUNT:
		var drop := MeshInstance3D.new()
		drop.mesh = mesh
		drop.material_override = _material
		drop.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(drop)
		drop.scale = Vector3.ONE * _rng.randf_range(.50, 1.3)
		var spread := Vector3(_rng.randf_range(-.8, .8), _rng.randf_range(.0, 1.1), _rng.randf_range(-.8, .8))
		var velocity := direction.normalized() * _rng.randf_range(.35, 1.4) + spread
		droplets.append({"mesh": drop, "velocity": velocity, "remaining": _rng.randf_range(.65, 1.35)})

func _physics_process(delta: float) -> void:
	age += delta
	if age >= LIFETIME:
		queue_free()
		return
	for index in range(droplets.size() - 1, -1, -1):
		var drop := droplets[index]
		var display: MeshInstance3D = drop.mesh
		var before := display.global_position
		drop.velocity += Vector3.DOWN * 7.5 * delta
		var after: Vector3 = before + drop.velocity * delta
		var query := PhysicsRayQueryParameters3D.create(before, after, 2)
		var contact := get_world_3d().direct_space_state.intersect_ray(query)
		drop.remaining -= delta
		if not contact.is_empty():
			_add_stain(contact.position, contact.normal)
		if not contact.is_empty() or drop.remaining <= 0.0:
			display.queue_free()
			droplets.remove_at(index)
		else:
			display.global_position = after
	# Subtle drying and a short disappearance, bounded independently of corpses.
	if age > LIFETIME - 2.0:
		for stain in stains:
			stain.scale = Vector3.ONE * maxf(.001, (LIFETIME - age) * .5)

func _add_stain(point: Vector3, normal: Vector3) -> void:
	if stains.size() >= MAX_STAINS: return
	var display := MeshInstance3D.new()
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var radius := _rng.randf_range(.045, .13)
	var contour := PackedVector3Array()
	for index in 18:
		var angle := float(index) * TAU / 18
		var length := radius * _rng.randf_range(.70, 1.2)
		contour.append(Vector3(cos(angle) * length, 0, sin(angle) * length * .72))
	for index in 18:
		for vertex: Vector3 in [Vector3.ZERO, contour[(index + 1) % 18], contour[index]]:
			surface.set_normal(Vector3.UP)
			surface.add_vertex(vertex)
	display.mesh = surface.commit()
	display.material_override = _material
	display.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(display)
	var up := normal.normalized()
	var tangent := up.cross(Vector3.FORWARD).normalized() if absf(up.dot(Vector3.FORWARD)) < .95 else up.cross(Vector3.RIGHT).normalized()
	display.global_transform = Transform3D(Basis(tangent, up, tangent.cross(up)), point + up * (.004 + stains.size() * .00015))
	stains.append(display)
