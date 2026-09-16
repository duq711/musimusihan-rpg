extends SceneTree
const STUDIO = preload("res://tests/sword_shield_preview.gd")
const OUT = "res://../exports/Sword_Shield_Manual_Edit/"
func v(p: Vector3): return [p.x,p.y,p.z]
func m(t: Transform3D): return [v(t.basis.x),v(t.basis.y),v(t.basis.z),v(t.origin)]
func _init(): call_deferred("run")
func run():
	var saved = ExpeditionSession.capture_snapshot();var cursor = Input.mouse_mode
	var sandbox = root.get_node("TestRoomSandbox");sandbox.begin()
	var vp = STUDIO.create_studio_viewport();root.add_child(vp)
	var f = STUDIO.PREVIEW.populate_viewport(vp);var p = f.player
	await physics_frame;await physics_frame
	assert(STUDIO.configure_pose(f,"idle"))
	var inv: Transform3D = p.camera.global_transform.affine_inverse()
	var export_root = Node3D.new();root.add_child(export_root)
	var report = {"sides":{},"weights":{},"bones":{}}
	for side in ["right","left"]:
		var arm = p.weapon_arm if side == "right" else p.shield_arm
		var pivot = p.weapon_pivot if side == "right" else p.shield_pivot
		var hand = p.get_first_person_motion_snapshot().hand_contacts["sword" if side == "right" else "shield"].actual
		var forearm = arm.get("_forearm")
		var wrist: Vector3 = arm.to_global(arm.REST_WRIST) if side == "right" else arm.global_position
		var elbow: Vector3 = arm.to_global(arm.get("_fitted_elbow")) if side == "right" else forearm.to_global(Vector3(0,0,0.26))
		var shoulder: Vector3 = arm.to_global(arm.get("_fitted_shoulder")) if side == "right" else p.camera.to_global(Vector3(-.29,-.34,.1))
		report.sides[side] = {"wrist":v(inv*wrist),"elbow":v(inv*elbow),"shoulder":v(inv*shoulder),"grip":v(inv*hand)}
		if side == "right": report.right_source_to_editor = m(inv*arm.global_transform*arm.SOURCE_READY.affine_inverse())
		for src in pivot.find_children("*","MeshInstance3D",true,false):
			if not src.is_visible_in_tree() or src.mesh == null: continue
			var copy = MeshInstance3D.new();copy.name = side + "__" + str(src.name)
			var mesh = ArrayMesh.new();var samples = []
			var skel = src.get_node_or_null(src.skeleton) if src.skin != null else null
			for surface in src.mesh.get_surface_count():
				var a = src.mesh.surface_get_arrays(surface).duplicate(true)
				var verts: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
				var normals: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
				var skinning = skel is Skeleton3D and a[Mesh.ARRAY_BONES] != null
				var stride = int(a[Mesh.ARRAY_BONES].size()/verts.size()) if skinning else 0
				for i in verts.size():
					var point: Vector3 = src.global_transform * verts[i]
					var normal: Vector3 = src.global_basis.inverse().transposed()*normals[i]
					var weights = {}
					if skinning:
						point = Vector3.ZERO;normal = Vector3.ZERO
						for k in stride:
							var w: float = a[Mesh.ARRAY_WEIGHTS][i*stride+k]
							if w < 0.00001: continue
							var bind: int = a[Mesh.ARRAY_BONES][i*stride+k]
							var b: int = src.skin.get_bind_bone(bind)
							if b < 0: b = skel.find_bone(src.skin.get_bind_name(bind))
							assert(b >= 0)
							var xf: Transform3D = skel.global_transform*skel.get_bone_global_pose(b)*src.skin.get_bind_pose(bind)
							point += (xf*verts[i])*w
							normal += (xf.basis.inverse().transposed()*normals[i])*w
							weights[str(skel.get_bone_name(b))] = w
							report.bones[side+"__"+str(skel.get_bone_name(b))] = m(inv*skel.global_transform*skel.get_bone_global_pose(b))
					verts[i] = inv*point;normals[i] = (inv.basis*normal).normalized()
					if skinning: samples.append({"p":v(verts[i]),"w":weights})
				a[Mesh.ARRAY_VERTEX] = verts;a[Mesh.ARRAY_NORMAL] = normals
				a[Mesh.ARRAY_BONES] = null;a[Mesh.ARRAY_WEIGHTS] = null;a[Mesh.ARRAY_TANGENT] = null
				mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,a)
				mesh.surface_set_material(surface,src.get_active_material(surface))
			copy.mesh = mesh;export_root.add_child(copy);copy.owner = export_root
			if not samples.is_empty():report.weights[str(copy.name)] = samples
	var doc = GLTFDocument.new();var state = GLTFState.new()
	assert(doc.append_from_scene(export_root,state) == OK)
	assert(doc.write_to_filesystem(state,ProjectSettings.globalize_path(OUT+"current_game_grips.glb")) == OK)
	var file = FileAccess.open(OUT+"current_game_grips.json",FileAccess.WRITE);file.store_string(JSON.stringify(report));file.close()
	vp.queue_free();export_root.queue_free();await process_frame;sandbox.finish()
	assert(saved == ExpeditionSession.capture_snapshot() and cursor == Input.mouse_mode)
	print("HAND EDITOR EXPORT PASS");quit()
