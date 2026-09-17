import bpy
from pathlib import Path


root = Path(bpy.data.filepath).parent
mesh = bpy.data.objects["Body_Skin_GameReady"]
armature = next(mod.object for mod in mesh.modifiers if mod.type == "ARMATURE")
for def_only in (False, True):
    bpy.ops.object.select_all(action="DESELECT")
    mesh.select_set(True)
    armature.select_set(True)
    bpy.context.view_layer.objects.active = armature
    path = root / f"skin_test_{'def' if def_only else 'all'}.glb"
    bpy.ops.export_scene.gltf(
        filepath=str(path),
        export_format="GLB",
        use_selection=True,
        export_skins=True,
        export_def_bones=def_only,
        export_armature_object_remove=False,
        export_animations=False,
        export_apply=False,
    )
    print("EXPORTED", path)
