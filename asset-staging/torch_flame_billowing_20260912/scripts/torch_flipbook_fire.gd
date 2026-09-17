extends RefCounted
## Unity Labs Flame02 (CC0), 64 frames in a 16 x 4 atlas.
const ATLAS = preload("res://assets/vfx/unity_flame/Flame02_16x4.png")
const SHADER = preload("res://assets/vfx/unity_flame/flipbook_fire.gdshader")
const CLOTH_BASE := 0.44
const CLOTH_TOP := 0.81
static func add_flame(root: Node3D, label: String, offset: Vector3, size: Vector2, angle: float, phase: float, strength: float) -> void:
	var card := MeshInstance3D.new()
	card.name = label
	var quad := QuadMesh.new();quad.size=size
	card.mesh=quad;card.position=offset+Vector3.UP*size.y*.5;card.rotation.y=angle
	card.extra_cull_margin = 0.6
	card.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material:=ShaderMaterial.new();material.shader=SHADER
	material.set_shader_parameter("flame_atlas",ATLAS)
	material.set_shader_parameter("phase",phase)
	material.set_shader_parameter("height_offset", offset.y + size.y * 0.5)
	material.set_shader_parameter("strength",strength)
	card.material_override=material
	root.add_child(card)
static func create() -> Node3D:
	var root:=Node3D.new();root.set_meta("unity_flame_flipbook",true)
	# Circumferential emitters start at the bottom of the oiled wrapping.
	for i in 8:
		var angle:=TAU*float(i)/8.0
		add_flame(root,"ClothFlame_%d"%i,Vector3(sin(angle)*.085,0,cos(angle)*.085),Vector2(.21,.64),angle,float(i)*7.7,.4)
	# Crossing upper tongues keep the flame readable around the torch.
	for i in 3:
		add_flame(root,"TipFlame_%d"%i,Vector3(0,CLOTH_TOP-CLOTH_BASE-.06,0),Vector2(.36,.64),PI*float(i)/3.0,11.0+float(i)*17.0,.65)
	return root

## World-space lean follows the requested movement direction, with a soft stop.
static func update_flow(root: Node3D, lateral_velocity: Vector3, delta: float) -> void:
	var target := (lateral_velocity * 0.10).limit_length(0.48)
	var lean: Vector3 = root.get_meta("movement_lean", Vector3.ZERO)
	lean = lean.lerp(target, 1.0 - exp(-8.0 * maxf(delta, 0.0)))
	root.set_meta("movement_lean", lean)
	for card in root.get_children():
		if card is MeshInstance3D:
			card.material_override.set_shader_parameter("movement_lean", card.global_basis.inverse() * lean)
