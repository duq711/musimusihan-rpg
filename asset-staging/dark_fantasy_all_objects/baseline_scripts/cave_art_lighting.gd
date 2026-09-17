extends Node3D
## Sparse survey lamps at wet working faces, built against real rock triangles.
const LAYOUT := preload("res://scripts/cave_layout.gd")
var ready_for_inspection := false
var contacts: Array[Dictionary] = []
var _geometry: Node3D
var _excluded: Array[RID] = []

func build(geometry: Node3D) -> void:
	_geometry = geometry
	await get_tree().physics_frame
	await get_tree().physics_frame
	if not is_inside_tree():
		return
	for body in geometry.find_children("*", "StaticBody3D", true, false):
		if not str(body.name).begins_with("Collision_Terrain_"):
			_excluded.append(body.get_rid())
	# Working faces, not route centres; each candidate is projected to rock.
	var sites := [
		[Vector3(-53.3,2.40,-15.1),Vector3(1,0,0.45)],
		[Vector3(-53.5,2.30,-11.0),Vector3(0.05,0,1)],
		[Vector3(-52.5,2.40,-30.5),Vector3(-1,0,-0.15)],
		[Vector3(10.0,2.55,-48.0),Vector3(1,0,0.4)],
		[Vector3(34.0,2.45,29.0),Vector3(0,0,-1)],
		[Vector3(43.0,2.45,7.0),Vector3(1,0,0)],
	]
	for site in sites:
		_add_lamp(site[0], site[1])
	ready_for_inspection = true

func _ray(from: Vector3, to: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from,to,2,_excluded)
	query.hit_back_faces = true
	return get_world_3d().direct_space_state.intersect_ray(query)

func _add_lamp(from: Vector3, direction: Vector3) -> void:
	var hit := _ray(from,from+direction.normalized()*12.0)
	if hit.is_empty() or absf(hit.normal.y)>0.58:
		return
	var normal: Vector3 = hit.normal
	if normal.dot(direction)>0:
		normal = -normal
	var point: Vector3 = hit.position
	var normal_flat := Vector3(normal.x,0,normal.z).normalized()
	var wick := point+normal_flat*0.48
	if wick.y-_geometry.floor_height(Vector2(wick.x,wick.z))<1.85:
		return
	for existing: Dictionary in _geometry.get_build_info().get("lights", []):
		var placed: Array = existing.position
		if wick.distance_to(Vector3(placed[0],placed[1],placed[2]))<1.6:
			return
	var timber := StandardMaterial3D.new()
	timber.albedo_texture = load("res://assets/3d/abandoned_mine/textures/rough_wood_albedo_2k.jpg")
	timber.normal_texture = load("res://assets/3d/abandoned_mine/textures/rough_wood_normal_gl_2k.jpg")
	timber.normal_enabled = true
	timber.albedo_color = Color(0.36,0.30,0.22)
	timber.roughness = 0.88
	var iron := StandardMaterial3D.new()
	iron.albedo_color = Color(0.085,0.072,0.052)
	iron.roughness = 0.62
	iron.metallic = 0.55
	var upper := _ray(point+Vector3.UP*.45+normal_flat*.85,point+Vector3.UP*.45-normal_flat*.85)
	var lower := _ray(point-Vector3.UP*.36+normal_flat*.85,point-Vector3.UP*.36-normal_flat*.85)
	if upper.is_empty() or lower.is_empty():
		return
	var top: Vector3 = upper.position-normal_flat*.055
	var bottom: Vector3 = lower.position-normal_flat*.055
	var mount := Node3D.new()
	mount.name = "WetWorkingFaceLamp_%02d" % contacts.size()
	add_child(mount)
	_beam(mount,bottom,top,.22,.22,timber)
	var tip := wick+Vector3.UP*.40
	_beam(mount,top,tip,.115,.12,timber)
	_beam(mount,bottom+Vector3.UP*.16,tip-normal_flat*.05,.07,.075,iron)
	# Reuse the production Blender lantern cage/wick, not a billboard substitute.
	var original: Dictionary = _geometry.get_build_info().prop_contact.wall_lanterns[0]
	var old_wick := Vector3(original.wick_godot[0],original.wick_godot[1],original.wick_godot[2])
	var old_normal := Vector3(original.wall_normal_godot[0],0,original.wall_normal_godot[2])
	var rotation_y := atan2(normal_flat.x,normal_flat.z)-atan2(old_normal.x,old_normal.z)
	var rotate := Basis(Vector3.UP,rotation_y)
	var transform_from_source := Transform3D(rotate,wick-rotate*old_wick)
	var copies := 0
	for source in _geometry.blender_mine.find_children(str(original.name)+"*", "MeshInstance3D",true,false):
		if str(source.name).contains("AgedOak"):
			continue
		var copy := MeshInstance3D.new()
		copy.mesh = source.mesh
		copy.name = "BlenderLanternPart_%d" % copies
		copy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mount.add_child(copy)
		copy.global_transform = transform_from_source*source.global_transform
		copies += 1
	var light := OmniLight3D.new()
	light.name = "SurveyLampLight"
	light.position = wick
	light.light_color = Color(1.0,0.71,0.37)
	light.light_energy = 3.3
	light.omni_range = 7.2
	light.omni_attenuation = 1.5
	light.shadow_enabled = true
	light.light_size = 0.075
	light.light_volumetric_fog_energy = 0.18
	light.distance_fade_enabled = true
	light.distance_fade_begin = 24
	light.distance_fade_length = 8
	mount.add_child(light)
	contacts.append({"name":mount.name,"wall_point":point,"normal":normal_flat,"upper_contact":top,"lower_contact":bottom,"wick":wick,"blender_parts":copies})

func _beam(parent: Node3D, a: Vector3, b: Vector3, width: float, depth: float, material: Material) -> void:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(width,a.distance_to(b),depth)
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	visual.material_override = material
	parent.add_child(visual)
	visual.position = (a+b)*0.5
	var up := (b-a).normalized()
	var side := Vector3.RIGHT if absf(up.dot(Vector3.RIGHT))<0.9 else Vector3.FORWARD
	var x := up.cross(side).normalized()
	visual.basis = Basis(x,up,x.cross(up).normalized())

func get_state_snapshot() -> Dictionary:
	return {"ready":ready_for_inspection,"lamp_count":contacts.size(),"contacts":contacts.duplicate(true)}
