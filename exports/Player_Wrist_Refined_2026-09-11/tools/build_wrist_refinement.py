"""Background-only local wrist refinement; original files and fingers remain intact."""
import argparse
import hashlib
import json
import math
import platform
import struct
import sys
from datetime import datetime, timezone
from pathlib import Path
import bpy
from mathutils import Vector
sys.path.insert(0, str(Path(__file__).resolve().parent))
from wrist_geometry import refine_hand, build_profiles, taper_forearm, replace_cuff, native_points, deform_preview_point
DIGITS = ("thumb", "index", "middle", "ring", "little")
KEYS = [f"Joint_{digit}_{joint}" for digit in DIGITS for joint in range(3)]


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

def mesh_signature(obj):
    h = hashlib.sha256()
    for vertex in obj.data.vertices:
        h.update(struct.pack("<3f", *vertex.co))
        for group in vertex.groups:
            h.update(struct.pack("<If", group.group, group.weight))
    for polygon in obj.data.polygons:
        h.update(struct.pack(f"<{len(polygon.vertices)}I", *polygon.vertices))
    return h.hexdigest()

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

def export_native(scene, side_objects, holder, output_path):
    temporary = bpy.data.scenes.new("Articulated_Export_Native")
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
               "export_morph_tangent": False}
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
    return glb_morph_report(output_path)


def morph_deltas(skin):
    basis = skin.data.shape_keys.key_blocks['Basis']
    h = hashlib.sha256()
    for key in skin.data.shape_keys.key_blocks:
        if key.name == 'Basis':
            continue
        h.update(key.name.encode())
        for first, second in zip(key.data, basis.data):
            h.update(struct.pack('<3f', *(first.co - second.co)))
    return h.hexdigest()


def bounds(points):
    return {'min': [min(point[i] for point in points) for i in range(3)],
            'max': [max(point[i] for point in points) for i in range(3)]}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--input-dir', type=Path, required=True)
    parser.add_argument('--output-dir', type=Path, required=True)
    args = parser.parse_args(sys.argv[sys.argv.index('--') + 1:])
    assert bpy.app.background, 'Use a separate background process'
    source, output = args.input_dir.resolve(), args.output_dir.resolve()
    files = {name: source / name for name in ('bilateral_hands_articulated.blend', 'left_hand_articulated.glb', 'right_hand_articulated.glb', 'build_report.json')}
    assert all(path.is_file() for path in files.values())
    assert source != output and source not in output.parents
    assert not output.exists() or (output.is_dir() and not any(output.iterdir())), 'Use a new output directory'
    source_hashes = {name: digest(path) for name, path in files.items()}
    output.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.open_mainfile(filepath=str(files['bilateral_hands_articulated.blend']))
    scene = bpy.data.scenes['Bilateral_Articulated_Review']
    scene.name = 'Bilateral_Wrist_Refined_Review'
    activate(scene)
    report = {'status': 'building', 'utc': datetime.now(timezone.utc).isoformat(),
              'host': {'platform': platform.platform(), 'blender_binary': bpy.app.binary_path,
                       'blender_version': bpy.app.version_string, 'background': bpy.app.background},
              'source_sha256': source_hashes, 'hands': {}, 'renders': {},
              'scope': 'Local wrist taper and rounded leather cuff, without changing finger or nail geometry',
              'runtime_contract': {'version': 1, 'start_z': .014, 'end_z': .075,
                 'coordinate_system': 'Godot adapter native meters, +Z toward forearm',
                 'center': 'lerp(axis_center, ForearmFit * axis_center, smoothstep)',
                 'section': 'quaternion slerp identity to forearm rotation; preserve radial section'}}
    hands = {}
    for side in ('left', 'right'):
        holder = scene.objects[side.upper() + '_PreviewTranslationOnly']
        objects = descendants(holder)
        rig = next(obj for obj in objects if obj.type == 'ARMATURE')
        skin = next(obj for obj in objects if obj.type == 'MESH' and 'anatomicalhand' in obj.name.lower())
        forearm = next(obj for obj in objects if obj.type == 'MESH' and 'forearm' in obj.name.lower())
        cuff = next(obj for obj in objects if obj.type == 'MESH' and 'wristcuff' in obj.name.lower())
        nails = {obj.name: mesh_signature(obj) for obj in objects if obj.name.startswith('Nail_')}
        bones = bone_signature(rig)
        morph_before = morph_deltas(skin)
        original_skin = [vertex.co.copy() for vertex in skin.data.vertices]
        source_bounds = {obj.name: bounds(native_points(obj, holder)) for obj in (skin, forearm, cuff)}
        hand_report = refine_hand(skin, holder)
        assert all(skin.data.vertices[i].co == original_skin[i] for i in hand_report['preserved_vertex_indices'])
        assert morph_before == morph_deltas(skin), 'Relative finger morph deltas changed'
        distal, proximal, original_arm_tree = build_profiles(skin, forearm, holder)
        arm_report = taper_forearm(forearm, holder, distal, proximal, original_arm_tree)
        cuff_report = replace_cuff(cuff, holder, distal, proximal)
        bpy.context.view_layer.update()
        assert bones == bone_signature(rig), 'Rest bones changed'
        assert nails == {obj.name: mesh_signature(obj) for obj in objects if obj.name.startswith('Nail_')}
        exported = export_native(scene, objects, holder, output / f'{side}_hand_wrist_refined.glb')
        report['hands'][side] = {'skin_object': skin.name, 'rig_object': rig.name,
            'cuff_object': cuff.name, 'cuff_parent': cuff.parent.name, 'hand_refinement': hand_report,
            'forearm_refinement': arm_report, 'cuff': cuff_report, 'source_bounds': source_bounds,
            'output_bounds': {obj.name: bounds(native_points(obj, holder)) for obj in (skin, forearm, cuff)},
            'preserved_morph_delta_sha256': morph_before, 'preserved_nail_sha256': nails,
            'rest_bones': bones, 'native_wrist_blender_m': [0, -.05624999850988388, 0], 'export': exported}
        hands[side] = (holder, objects, rig, skin, forearm, cuff)
    bpy.ops.wm.save_as_mainfile(filepath=str(output / 'bilateral_hands_wrist_refined.blend'))
    # All following mutations are disposable render poses, never saved to the .blend.
    holder, objects, rig, skin, forearm, cuff = hands['left']
    for obj in hands['right'][1]:
        obj.hide_render = True
    for obj in objects:
        if obj.type == 'MESH' and 'upperarm' in obj.name.lower():
            obj.hide_render = True
    rest_forearm, rest_cuff = native_points(forearm, holder), native_points(cuff, holder)
    rest_forearm_local = [vertex.co.copy() for vertex in forearm.data.vertices]
    rest_cuff_local = [vertex.co.copy() for vertex in cuff.data.vertices]
    arm_inverse, cuff_inverse = forearm.matrix_world.inverted() @ holder.matrix_world, cuff.matrix_world.inverted() @ holder.matrix_world
    camera = scene.camera
    camera.data.ortho_scale = .205
    scene.cycles.samples = 40
    scene.render.resolution_x, scene.render.resolution_y = 1400, 1100
    scene.render.resolution_percentage = 100
    configurations = [
        ('wrist_dorsum', (0, 0, 1), None), ('wrist_palm', (0, 0, -1), None),
        ('wrist_side', (1, 0, .06), None),
        ('wrist_bend_dorsum', (0, -.05, 1), (-.174021, .052519, .271910)),
        ('wrist_bend_palm', (0, 0, -1), (.174021, -.090519, .271910)),
        ('wrist_bend_side_60deg', (0, -.25, 1), (.281458, 0, .1625)),
    ]
    for name, direction, elbow in configurations:
        for vertex, point in zip(forearm.data.vertices, rest_forearm_local):
            vertex.co = point
        for vertex, point in zip(cuff.data.vertices, rest_cuff_local):
            vertex.co = point
        if elbow:
            for vertex, point in zip(forearm.data.vertices, rest_forearm):
                vertex.co = arm_inverse @ deform_preview_point(point, elbow, False)
            for vertex, point in zip(cuff.data.vertices, rest_cuff):
                vertex.co = cuff_inverse @ deform_preview_point(point, elbow, True)
        forearm.data.update(); cuff.data.update(); bpy.context.view_layer.update()
        current = native_points(cuff, holder)
        center_native = sum(current, Vector()) / len(current)
        center_native.y += .006
        center = holder.matrix_world @ center_native
        camera.location = center + Vector(direction).normalized() * 1.2
        camera.rotation_euler = (center - camera.location).to_track_quat('-Z', 'Y').to_euler()
        scene.render.filepath = str(output / f'{name}.png')
        bpy.ops.render.render(write_still=True)
        report['renders'][name] = {'file': Path(scene.render.filepath).name,
                                   'elbow_godot_native_m': elbow, 'requires_visual_review': True}
    assert source_hashes == {name: digest(path) for name, path in files.items()}
    report['status'] = 'built_pending_independent_surface_and_runtime_verification'
    report['outputs'] = {path.name: {'bytes': path.stat().st_size, 'sha256': digest(path)} for path in output.iterdir() if path.is_file()}
    (output / 'build_report.json').write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
    print('WRIST_REFINEMENT_BUILD_COMPLETE', output)


if __name__ == '__main__':
    main()
