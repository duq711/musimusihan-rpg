extends RefCounted
## Painting, seams and braces are visual only; the training room retains its
## original solid target collider, lane centres and exact shot distances.
const SURFACES := preload("res://scripts/dark_fantasy_materials.gd")


static func add_target_timbers(board: Node3D) -> void:
	for index in range(9):
		var plank := _box(board, "TargetWeatheredPlank%02d" % index, Vector3(0.585, 5.0, 0.25), Vector3(-2.4 + float(index) * 0.6, 0, 0), SURFACES.old_oak(Color(0.37, 0.34, 0.285), 0.68))
		plank.rotation.z = 0.0018 * sin(float(index) * 7.2)
	for height in [-1.74, 1.74]:
		_box(board, "RearCrossBrace", Vector3(4.98, 0.38, 0.11), Vector3(0, height, -0.178), SURFACES.old_oak(Color(0.32, 0.30, 0.26), 0.8))
		for side in [-1.0, 1.0]:
			var nail := MeshInstance3D.new()
			nail.name = "RearBraceForgedNail"
			var sphere := SphereMesh.new()
			sphere.radius = 0.075
			sphere.height = 0.045
			sphere.radial_segments = 10
			sphere.rings = 4
			nail.mesh = sphere
			nail.rotation.x = PI / 2.0
			nail.position = Vector3(side * 2.15, height, -0.247)
			nail.material_override = SURFACES.pitted_iron()
			board.add_child(nail)


static func target_paint(color: Color) -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
uniform vec4 paint:source_color;
uniform sampler2D timber:source_color,filter_linear_mipmap_anisotropic,repeat_enable;
varying vec3 local_point;
float h(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
float n(vec2 p){vec2 i=floor(p),f=fract(p);f=f*f*(3.0-2.0*f);return mix(mix(h(i),h(i+vec2(1,0)),f.x),mix(h(i+vec2(0,1)),h(i+vec2(1,1)),f.x),f.y);}
void vertex(){local_point=VERTEX;}
void fragment(){
 vec2 p=local_point.xz; float board_cell=mod(p.x+2.7,0.6); if(board_cell<0.014||board_cell>0.586)discard;
 float scratch=n(p*vec2(35.0,2.0)); vec3 grain=texture(timber,p*0.68).rgb;
 float wear=0.82+0.18*scratch;
 ALBEDO=mix(grain*0.55,paint.rgb*(0.67+grain*0.38),wear); ROUGHNESS=0.99;
}
"""
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("paint", color)
	material.set_shader_parameter("timber", SURFACES.OAK)
	return material


static func decorate_lane(marker: MeshInstance3D, near: bool) -> void:
	marker.material_override = SURFACES.stone(Color(0.25, 0.26, 0.23), 1.3)
	var color := Color(0.42, 0.42, 0.25) if near else Color(0.24, 0.39, 0.45)
	var paint := SURFACES.create("stone", color, null, 3.0)
	for side in [-1.0, 1.0]:
		_box(marker, "LaneInsetBorder", Vector3(0.012, 0.001, 1.26), Vector3(side * 0.83, 0.008, 0), paint)
		_box(marker, "LaneInsetBorder", Vector3(1.67, 0.001, 0.012), Vector3(0, 0.008, side * 0.63), paint)
		for other in [-1.0, 1.0]:
			_box(marker, "LaneCornerMark", Vector3(0.014, 0.001, 0.105), Vector3(side * 0.76, 0.008, other * 0.625), paint)
			_box(marker, "LaneCornerMark", Vector3(0.105, 0.001, 0.014), Vector3(side * 0.825, 0.008, other * 0.56), paint)


static func _box(parent: Node3D, label: String, size: Vector3, at: Vector3, material: Material) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = label + "%02d" % parent.get_child_count()
	var mesh := BoxMesh.new()
	mesh.size = size
	instance.mesh = mesh
	instance.position = at
	instance.material_override = material
	parent.add_child(instance)
	return instance
