extends SkeletonModifier3D
## Physics proxies are unscaled. The source rig has a scaled root and detached
## hand/foot IK roots, so map explicit world poses without changing its skin.
var controller: Node3D

func _process_modification_with_delta(_delta: float) -> void:
	apply_physical_pose()

func apply_physical_pose() -> void:
	if not is_instance_valid(controller) or controller.phase not in ["simulating", "settled"]:
		return
	var rig := get_skeleton()
	var to_rig := rig.global_transform.affine_inverse()
	for entry: Dictionary in controller.pose_order:
		var body: RigidBody3D = entry.body
		rig.set_bone_global_pose(entry.bone, to_rig * body.global_transform * entry.body_to_bone)
