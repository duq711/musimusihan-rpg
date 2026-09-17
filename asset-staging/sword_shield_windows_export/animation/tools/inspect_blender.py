import bpy,json
from pathlib import Path
bpy.ops.wm.read_factory_settings(use_empty=True)
p=Path(__file__).resolve().parents[1]/"source/right_arm.glb"
bpy.ops.import_scene.gltf(filepath=str(p))
for o in bpy.context.scene.objects:
 print("OBJ",o.name,o.type,"parent",o.parent.name if o.parent else None,"world",[list(r) for r in o.matrix_world])
 if o.type=="ARMATURE":
  for b in o.data.bones: print("BONE",b.name,"parent",b.parent.name if b.parent else None,"rest",[list(r) for r in b.matrix_local])
print("EXPORT_OPTIONS",[(p.identifier,list(p.enum_items.keys()) if p.type=="ENUM" else p.type) for p in bpy.ops.export_scene.gltf.get_rna_type().properties if "anim" in p.identifier or p.identifier in ["export_cameras","export_image_format","export_materials","export_format"]])
