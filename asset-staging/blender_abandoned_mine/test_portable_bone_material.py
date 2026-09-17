"""Fast isolated background test of standard glTF bone texture bindings."""
import json
import struct
import sys
from pathlib import Path
import bpy
ROOT=Path(__file__).resolve().parent
sys.path.insert(0,str(ROOT))
import bone_props
bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)
bpy.ops.mesh.primitive_plane_add(size=1)
obj=bpy.context.object
obj.name="GiantBeast_MaterialProbe"
report=bone_props.apply_portable_bone_material()
assert report["mesh_objects"]==[obj.name],report
assert set(n.type for n in obj.data.materials[0].node_tree.nodes)<={"OUTPUT_MATERIAL","BSDF_PRINCIPLED","TEX_COORD","TEX_IMAGE","NORMAL_MAP"}
out=ROOT/"qa"/"portable_bone_material_probe.glb"
bpy.ops.export_scene.gltf(filepath=str(out),export_format="GLB",export_materials="EXPORT",export_animations=False,export_cameras=False,export_lights=False)
raw=out.read_bytes()
assert raw[:4]==b"glTF"
length,kind=struct.unpack_from("<II",raw,12)
assert kind==0x4E4F534A
gltf=json.loads(raw[20:20+length])
mat=gltf["materials"][0]
pbr=mat["pbrMetallicRoughness"]
assert "baseColorTexture" in pbr,pbr
assert "metallicRoughnessTexture" in pbr,pbr
assert "normalTexture" in mat,mat
assert len(gltf["images"])==3,gltf["images"]
assert all("bufferView" in image for image in gltf["images"])
report.update({"passed":True,"glb_bytes":len(raw),"embedded_images":3,"glTF_material":mat})
(ROOT/"qa"/"portable_bone_material_report.json").write_text(json.dumps(report,indent=2))
print("PORTABLE_BONE_MATERIAL_PASS "+json.dumps(report))
