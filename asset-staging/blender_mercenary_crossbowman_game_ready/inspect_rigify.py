import bpy
import addon_utils


bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)

addon_utils.enable("rigify", default_set=False, persistent=False)
print("RIGIFY_CHECK", addon_utils.check("rigify"))
print("HAS_HUMAN_METARIG_OPERATOR", hasattr(bpy.ops.object, "armature_human_metarig_add"))

bpy.ops.object.armature_human_metarig_add()
metarig = bpy.context.active_object
print("METARIG", metarig.name, metarig.dimensions[:])
for name in (
    "spine",
    "spine.003",
    "spine.004",
    "spine.006",
    "upper_arm.L",
    "forearm.L",
    "hand.L",
    "thigh.L",
    "shin.L",
    "foot.L",
    "toe.L",
):
    bone = metarig.data.bones.get(name)
    if bone:
        print("BONE", name, "head", tuple(round(value, 5) for value in bone.head_local), "tail", tuple(round(value, 5) for value in bone.tail_local))

print("RIGIFY_TYPES", sorted({pose_bone.rigify_type for pose_bone in metarig.pose.bones if pose_bone.rigify_type}))
