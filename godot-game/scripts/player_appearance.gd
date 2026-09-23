extends RefCounted
## Shared, real 3D character used by the player and the inventory portrait.

const MODEL_PATH := "res://assets/3d/player/gravebound_player.glb"
const OUTFIT_PATH := "res://assets/3d/player/medival_outfit.glb"
const BODY_LAYER := 1 << 17
const APPEARANCE_ID := "gravebound_medival_source_outfit_v3"
const OUTFIT_PARTS: Array[String] = [
	"Medival_ShirtUpper", "Medival_Pants", "Medival_Belt",
	"Medival_Shoe_L", "Medival_Shoe_R",
]
const RETIRED_OUTFIT_PARTS: Array[String] = [
	"Gravebound_QuiltedTorso", "Gravebound_FP_L_Arm", "Gravebound_FP_R_Arm",
	"Gravebound_Trousers_L", "Gravebound_Trousers_R",
	"Gravebound_LeatherBelt", "Gravebound_BeltBuckle", "Gravebound_BeltTongue",
	"Gravebound_Pouch_L", "Gravebound_Pouch_R",
	"Gravebound_PouchFlap_L", "Gravebound_PouchFlap_R",
]
const CLOTH_COLOR := Color(0.19, 0.175, 0.15)
const LEATHER_COLOR := Color(0.095, 0.075, 0.057)
const SKIN_COLOR := Color(0.46, 0.365, 0.30)
static var _cloth: StandardMaterial3D
static var _leather: StandardMaterial3D
static var _skin: StandardMaterial3D


static func create_body() -> Node3D:
	var scene := load(MODEL_PATH) as PackedScene
	assert(scene != null, "The player appearance must use the production 3D model.")
	var body := scene.instantiate() as Node3D
	body.name = "GraveboundPlayerBody"
	body.set_meta("appearance_id", APPEARANCE_ID)
	body.set_meta("model_path", MODEL_PATH)
	body.set_meta("outfit_path", OUTFIT_PATH)
	# Keep the source GLB intact for gameplay and asset inspection, but render
	# only the supplied garments in the player and inventory portrait.
	var original_parts := body.find_children("*", "MeshInstance3D", true, false)
	assert(original_parts.size() == 20, "The source player must keep all original mesh parts.")
	for original_part in original_parts:
		(original_part as MeshInstance3D).visible = false
	var outfit_scene := load(OUTFIT_PATH) as PackedScene
	assert(outfit_scene != null, "The supplied Medival clothing must be imported.")
	var outfit := outfit_scene.instantiate() as Node3D
	outfit.name = "MedivalOutfit"
	body.add_child(outfit)
	var outfit_parts: Array[String] = []
	for node in outfit.find_children("*", "MeshInstance3D", true, false):
		var part := node as MeshInstance3D
		outfit_parts.append(str(part.name))
	assert(outfit_parts.size() == OUTFIT_PARTS.size(), "The replacement Medival outfit must contain its five original clothing pieces.")
	for name in OUTFIT_PARTS:
		assert(name in outfit_parts, "Missing original Medival clothing piece: " + name)
	# The supplied garment is an intact, unrigged source mesh. Deforming a
	# separately cut hem here would reopen the shirt and corrupt its silhouette.
	assign_body_layer(body)
	return body


static func assign_body_layer(node: Node) -> void:
	if node is GeometryInstance3D:
		node.layers = BODY_LAYER
	for child in node.get_children():
		assign_body_layer(child)


static func cloth_material() -> StandardMaterial3D:
	if _cloth == null:
		_cloth = _rough_material(CLOTH_COLOR, 0.96, 36.0)
	return _cloth


static func leather_material() -> StandardMaterial3D:
	if _leather == null:
		_leather = _rough_material(LEATHER_COLOR, 0.80, 22.0)
	return _leather


static func skin_material() -> StandardMaterial3D:
	if _skin == null:
		_skin = StandardMaterial3D.new()
		_skin.albedo_color = SKIN_COLOR
		_skin.roughness = 0.88
	return _skin


static func _rough_material(color: Color, roughness: float, frequency: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	var noise := FastNoiseLite.new()
	noise.seed = 7107
	noise.frequency = 0.09
	noise.fractal_octaves = 3
	var bump := NoiseTexture2D.new()
	bump.width = 128
	bump.height = 128
	bump.noise = noise
	bump.as_normal_map = true
	bump.bump_strength = 0.18
	bump.seamless = true
	material.normal_enabled = true
	material.normal_texture = bump
	material.normal_scale = 0.35
	material.uv1_scale = Vector3(frequency, frequency, frequency)
	return material
