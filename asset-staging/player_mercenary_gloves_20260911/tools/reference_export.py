"""Native game export utilities retained from the previously verified hand workflow."""
import hashlib,json,struct,sys
from pathlib import Path
import bpy
DIGITS=("thumb","index","middle","ring","little")
KEYS=[f"Joint_{d}_{j}" for d in DIGITS for j in range(3)]
def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def activate(scene):
    bpy.context.window.scene = scene
    bpy.context.view_layer.update()

def descendants(parent):
    output = []
    for child in parent.children:
        output.append(child)
        output.extend(descendants(child))
    return output

def bone_signature(rig):
    return {bone.name: {"parent": bone.parent.name if bone.parent else None,
                        "matrix": [list(row) for row in bone.matrix_local]}
            for bone in rig.data.bones}

def glb_morph_report(path):
    data = path.read_bytes()
    size, kind = struct.unpack_from("<II", data, 12)
    document = json.loads(data[20:20 + size])
    assert kind == 0x4E4F534A
    morph_meshes = []
    for mesh in document["meshes"]:
        names = mesh.get("extras", {}).get("targetNames", [])
        if names:
            assert names == KEYS, f"Exported shape names/order changed: {names}"
            rows = []
            for primitive in mesh["primitives"]:
                targets = primitive.get("targets", [])
                assert len(targets) == 15, "Primitive lost corrective targets"
                assert all("POSITION" in target and "NORMAL" in target for target in targets), "Position/normal morph missing"
                rows.append({"vertices": document["accessors"][primitive["attributes"]["POSITION"]]["count"],
                             "target_count": len(targets), "position_and_normal": True})
            assert all(value == 0 for value in mesh.get("weights", [])), "Exported corrective is active in neutral asset"
            morph_meshes.append({"mesh": mesh.get("name"), "target_names": names, "primitives": rows})
    assert len(morph_meshes) == 1, "Only the anatomical hand mesh should have corrective morphs"
    assert len(document.get("skins", [])) == 1 and len(document["skins"][0]["joints"]) == 16
    for mesh in document["meshes"]:
        if "Nail_" in mesh.get("name", ""):
            assert not mesh.get("extras", {}).get("targetNames"), "Nail unexpectedly has corrective targets"
    return {"sha256": digest(path), "bytes": path.stat().st_size, "morph_meshes": morph_meshes,
            "skin_joints": [document["nodes"][j]["name"] for j in document["skins"][0]["joints"]]}

def repair_zero_export_tangents(path):
    """Apply the documented UV-frame fix only if Blender exported a zero tangent."""
    import runpy
    blob=path.read_bytes();size=struct.unpack_from('<I',blob,12)[0];document=json.loads(blob[20:20+size]);binary_start=20+size+8;has_zero=False
    for mesh in document['meshes']:
        for primitive in mesh['primitives']:
            tangent=primitive['attributes'].get('TANGENT')
            if tangent is None:continue
            accessor=document['accessors'][tangent];view=document['bufferViews'][accessor['bufferView']];offset=binary_start+view.get('byteOffset',0)+accessor.get('byteOffset',0);stride=view.get('byteStride',16)
            for index in range(accessor['count']):
                vector=struct.unpack_from('<3f',blob,offset+index*stride)
                if sum(value*value for value in vector)<1e-12:has_zero=True;break
    if not has_zero:return
    temporary=path.with_name(path.stem+'_valid_tangents.glb');report=path.with_name(path.stem+'_tangent_repair.json');script=Path(__file__).with_name('repair_export_tangents.py');arguments=sys.argv
    try:
        sys.argv=[str(script),'--input-glb',str(path),'--output-glb',str(temporary),'--report',str(report)]
        runpy.run_path(str(script),run_name='__main__')
    finally:sys.argv=arguments
    temporary.replace(path)

def export_native(scene, side_objects, holder, output_path):
    temporary = bpy.data.scenes.new("Realistic_Export_Native")
    roots = [obj for obj in side_objects if obj.parent == holder]
    for obj in side_objects:
        temporary.collection.objects.link(obj)
        scene.collection.objects.unlink(obj)
    for obj in roots:
        basis = obj.matrix_basis.copy()
        obj.parent = None
        obj.matrix_basis = basis
    activate(temporary)
    bpy.ops.object.select_all(action="DESELECT")
    for obj in side_objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = roots[0]
    options = {"filepath": str(output_path), "export_format": "GLB", "use_selection": True,
               "use_active_scene": True, "export_yup": True, "export_materials": "EXPORT",
               "export_skins": True, "export_influence_nb": 8, "export_animations": False,
               "export_apply": False, "export_extras": True, "export_cameras": False,
               "export_lights": False, "export_morph": True, "export_morph_normal": True,
               "export_morph_tangent": False, "export_tangents": True}
    props = bpy.ops.export_scene.gltf.get_rna_type().properties.keys()
    assert "export_morph" in props and "export_morph_normal" in props
    bpy.ops.export_scene.gltf(**{key: value for key, value in options.items() if key in props})
    for obj in roots:
        basis = obj.matrix_basis.copy()
        obj.parent = holder
        obj.matrix_basis = basis
    for obj in side_objects:
        scene.collection.objects.link(obj)
        temporary.collection.objects.unlink(obj)
    activate(scene)
    bpy.data.scenes.remove(temporary)
    repair_zero_export_tangents(output_path)
    return glb_morph_report(output_path)
