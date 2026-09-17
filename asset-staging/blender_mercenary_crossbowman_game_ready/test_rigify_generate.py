import bpy


bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)
bpy.ops.preferences.addon_enable(module="rigify")
bpy.ops.object.armature_human_metarig_add()
metarig = bpy.context.active_object
metarig.name = "metarig_test"
bpy.context.view_layer.objects.active = metarig
metarig.select_set(True)
print("GENERATE_POLL", bpy.ops.pose.rigify_generate.poll())
result = bpy.ops.pose.rigify_generate()
print("GENERATE_RESULT", result)
print("OBJECT_COUNT", len(bpy.context.scene.objects))
rig = next((obj for obj in bpy.context.scene.objects if obj.type == "ARMATURE" and obj != metarig), None)
if rig:
    print("RIG_BONES", len(rig.data.bones), "POSE_BONES", len(rig.pose.bones))
    print("RIG_DEFORM_BONES", sum(1 for bone in rig.data.bones if bone.use_deform))
    print("DEFORM_NAMES", [bone.name for bone in rig.data.bones if bone.use_deform])
