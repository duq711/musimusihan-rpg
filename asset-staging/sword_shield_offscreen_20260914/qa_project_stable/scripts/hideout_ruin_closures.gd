extends RefCounted
## Close unintended shell seams above doorways without changing their physics.
## Install before ruin masonry/weather finishing and immutable static batching.
const CONCEPT := preload("res://scripts/dungeon_concept_visual.gd")
const PIECES := [
	{"id": "EntranceArchHeader", "region": "entrance", "position": Vector3(0.0, 3.70, 20.18), "size": Vector3(4.06, 1.04, 0.40)},
	{"id": "EntranceCeilingEndJoint", "region": "entrance", "position": Vector3(0.0, 4.18, 20.09), "size": Vector3(8.0, 0.08, 0.30)},
	{"id": "EntranceCeilingWestJoint", "region": "entrance", "position": Vector3(-4.12, 4.18, 15.0), "size": Vector3(0.28, 0.08, 10.0)},
	{"id": "EntranceCeilingEastJoint", "region": "entrance", "position": Vector3(4.12, 4.18, 15.0), "size": Vector3(0.28, 0.08, 10.0)},
	{"id": "WorkshopDrainHeader", "region": "workshop", "position": Vector3(16.08, 3.74, -5.0), "size": Vector3(0.32, 0.88, 3.06)},
]


static func build(hideout: Node) -> int:
	var added := 0
	for piece: Dictionary in PIECES:
		var region: Node3D = hideout.region_nodes.get(piece.region)
		if region == null:
			continue
		var node_name := "RuinClosure_" + str(piece.id)
		if region.has_node(NodePath(node_name)):
			continue
		assert(not region.has_meta("static_stone_batches_built"), "Close ruin shell seams before stone batching")
		# Assembled chipped masonry includes its recessed mortar and boundary
		# seal. A plain box or shadow-only panel would leave visible black gaps.
		var architecture := CONCEPT.create_architecture(piece.size, "ossuary_wall")
		architecture.name = node_name
		architecture.position = piece.position
		architecture.set_meta("ruin_structure_closure", piece.duplicate(true))
		region.add_child(architecture)
		added += 1
	return added
