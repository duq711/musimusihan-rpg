extends SceneTree
func _init() -> void:
	for side: String in ["left","right"]:
		var base := "/Users/duq711gmail.com/Documents/ChatGPT/무시무시한 rpg/godot-game/assets/3d/player/fp_arms/"+side
		var doc := GLTFDocument.new()
		var state := GLTFState.new()
		assert(doc.append_from_file(base+".glb",state)==OK)
		var scene := doc.generate_scene(state)
		_prepare_textures(scene)
		var packed := PackedScene.new()
		assert(packed.pack(scene)==OK)
		assert(ResourceSaver.save(packed,base+".scn")==OK)
		print(side," BONES ",scene.find_child("Skeleton3D",true,false).get_bone_count())
		scene.free()
	quit()

func _prepare_textures(node: Node) -> void:
	if node is MeshInstance3D:
		for surface in node.mesh.get_surface_count():
			var mat := node.get_active_material(surface) as StandardMaterial3D
			if mat == null: continue
			mat.texture_filter=BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
			for property: String in ["albedo_texture","normal_texture","roughness_texture","metallic_texture"]:
				var tex:=mat.get(property) as Texture2D
				if tex==null:continue
				var image:=tex.get_image()
				if not image.has_mipmaps():
					image.generate_mipmaps(property=="normal_texture")
					mat.set(property,ImageTexture.create_from_image(image))
	for child in node.get_children():_prepare_textures(child)
