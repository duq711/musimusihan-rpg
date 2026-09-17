"""Save presentation-only delivery defaults and prove model data unchanged."""
import argparse
from array import array
import hashlib
import json
from pathlib import Path
import shutil
import struct
import sys

import bpy
from mathutils import Vector


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def value(item):
    if item is None or isinstance(item, (str, bool, int, float)):
        return item
    if isinstance(item, bpy.types.ID):
        return [item.bl_rna.identifier, item.name]
    if hasattr(item, 'items'):
        return {str(k): value(v) for k, v in item.items()}
    try:
        return [value(v) for v in item]
    except TypeError:
        return str(item)


def hashed(item):
    return hashlib.sha256(json.dumps(item, sort_keys=True, ensure_ascii=False).encode()).hexdigest()


def buffer_hash(collection, field, size, kind='f'):
    data = array(kind, [0]) * (len(collection) * size)
    collection.foreach_get(field, data)
    return hashlib.sha256(data.tobytes()).hexdigest()


def snapshot():
    meshes = {}
    for mesh in bpy.data.meshes:
        attributes = {}
        for attribute in mesh.attributes:
            if attribute.data_type in ('FLOAT', 'INT', 'BOOLEAN'):
                field, size, kind = 'value', 1, ('f' if attribute.data_type == 'FLOAT' else 'i')
            elif attribute.data_type in ('FLOAT_VECTOR', 'FLOAT2'):
                field, size, kind = 'vector', (3 if attribute.data_type == 'FLOAT_VECTOR' else 2), 'f'
            elif attribute.data_type in ('FLOAT_COLOR', 'BYTE_COLOR'):
                field, size, kind = 'color', 4, 'f'
            else:
                attributes[attribute.name] = {'type': attribute.data_type, 'domain': attribute.domain,
                                              'values': hashed([value(getattr(d, 'value', None)) for d in attribute.data])}
                continue
            attributes[attribute.name] = {'type': attribute.data_type, 'domain': attribute.domain,
                                          'values': buffer_hash(attribute.data, field, size, kind)}
        meshes[mesh.name] = {
            'vertices': buffer_hash(mesh.vertices, 'co', 3),
            'edges': buffer_hash(mesh.edges, 'vertices', 2, 'i'),
            'loops': buffer_hash(mesh.loops, 'vertex_index', 1, 'i'),
            'polygons': hashed([(list(p.vertices), p.material_index, p.use_smooth) for p in mesh.polygons]),
            'weights': hashed([[(g.group, g.weight) for g in v.groups] for v in mesh.vertices]),
            'materials': [m.name if m else None for m in mesh.materials],
            'uv': {u.name: buffer_hash(u.data, 'uv', 2) for u in mesh.uv_layers},
            'attributes': attributes,
            'shape_keys': ({k.name: {'positions': buffer_hash(k.data, 'co', 3),
                                    'value': k.value, 'relative_key': k.relative_key.name,
                                    'vertex_group': k.vertex_group, 'mute': k.mute}
                           for k in mesh.shape_keys.key_blocks} if mesh.shape_keys else None),
        }
    objects = {}
    for obj in bpy.data.objects:
        if obj.type == 'CAMERA':
            continue
        row = {'type': obj.type, 'data': obj.data.name if obj.data else None,
               'matrix_basis': value(obj.matrix_basis), 'matrix_parent_inverse': value(obj.matrix_parent_inverse),
               'parent': obj.parent.name if obj.parent else None,
               'groups': [(v.name, v.index, v.lock_weight) for v in obj.vertex_groups],
               'custom_properties': value(dict(obj.items())),
               'modifiers': [(m.name, m.type, m.show_viewport, m.show_render,
                              getattr(getattr(m, 'object', None), 'name', None)) for m in obj.modifiers]}
        if obj.type == 'ARMATURE':
            row['bones'] = {b.name: {'parent': b.parent.name if b.parent else None,
                                    'matrix': value(b.matrix_local), 'head': value(b.head_local),
                                    'tail': value(b.tail_local), 'deform': b.use_deform} for b in obj.data.bones}
            row['pose'] = {b.name: {'matrix_basis': value(b.matrix_basis),
                                   'rotation_mode': b.rotation_mode} for b in obj.pose.bones}
        objects[obj.name] = row
    materials = {}
    for material in bpy.data.materials:
        row = {'diffuse_color': value(material.diffuse_color), 'roughness': material.roughness,
               'metallic': material.metallic, 'use_nodes': material.use_nodes}
        if material.node_tree:
            row['nodes'] = {n.name: {'type': n.bl_idname,
                                    'inputs': [(s.name, value(getattr(s, 'default_value', None))) for s in n.inputs],
                                    'outputs': [(s.name, value(getattr(s, 'default_value', None))) for s in n.outputs],
                                    'image': getattr(getattr(n, 'image', None), 'name', None),
                                    'uv_map': getattr(n, 'uv_map', None),
                                    'operation': getattr(n, 'operation', None),
                                    'blend_type': getattr(n, 'blend_type', None),
                                    'interpolation': getattr(n, 'interpolation', None),
                                    'extension': getattr(n, 'extension', None)} for n in material.node_tree.nodes}
            row['links'] = sorted([(l.from_node.name, l.from_socket.identifier,
                                    l.to_node.name, l.to_socket.identifier) for l in material.node_tree.links])
        materials[material.name] = row
    images = {i.name: {'size': list(i.size), 'source': i.source, 'colorspace': i.colorspace_settings.name,
                       'alpha_mode': i.alpha_mode, 'channels': i.channels,
                       'packed': [hashlib.sha256(p.packed_file.data).hexdigest() for p in i.packed_files]}
              for i in bpy.data.images if i.type != 'RENDER_RESULT'}
    return {'meshes': {k: hashed(v) for k, v in meshes.items()},
            'objects': {k: hashed(v) for k, v in objects.items()},
            'materials': {k: hashed(v) for k, v in materials.items()}, 'images': images}


parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--output-dir', required=True, type=Path)
args = parser.parse_args(sys.argv[sys.argv.index('--') + 1:])
assert bpy.app.background
output = args.output_dir.resolve()
blend = output / 'bilateral_hands_realistic.blend'
backup = output.parents[1] / 'diagnostics' / 'bilateral_hands_realistic_before_review_setup.blend'
assert not backup.exists(), 'Preserve the first verified delivery file; do not overwrite backup.'
backup.parent.mkdir(parents=True, exist_ok=True)
shutil.copy2(blend, backup)
old_sha = sha(blend)
glbs = {p.name: sha(p) for p in output.glob('*.glb')}
bpy.ops.wm.open_mainfile(filepath=str(blend))
before = snapshot()
scene = bpy.data.scenes['Bilateral_Realistic_Review']
bpy.context.window.scene = scene
old_settings = {'camera': scene.camera.name, 'samples': scene.cycles.samples,
                'resolution': [scene.render.resolution_x, scene.render.resolution_y],
                'denoising': scene.cycles.use_denoising}
scene.cycles.samples = 24
scene.cycles.use_denoising = True
scene.render.resolution_x = 1600
scene.render.resolution_y = 1300
scene.render.resolution_percentage = 100
scene.render.filepath = '//bilateral_dorsum.png'
camera = scene.camera
camera.data.type = 'ORTHO'
camera.data.ortho_scale = .68
center = Vector((0, -.035, 0))
camera.location = center + Vector((0, 0, 1.2))
camera.rotation_euler = (center - camera.location).to_track_quat('-Z', 'Y').to_euler()
hidden_upperarms = []
for obj in scene.objects:
    if obj.type == 'MESH' and 'UpperArm' in obj.name:
        obj.hide_render = True
        obj.hide_set(True)
        hidden_upperarms.append(obj.name)
viewports = []
for screen in bpy.data.screens:
    for area in screen.areas:
        if area.type != 'VIEW_3D':
            continue
        space = area.spaces.active
        space.shading.type = 'MATERIAL'
        space.shading.use_scene_lights = True
        space.shading.use_scene_world = True
        space.overlay.show_overlays = False
        space.region_3d.view_perspective = 'CAMERA'
        space.region_3d.view_camera_zoom = 0
        space.region_3d.view_camera_offset = (0, 0)
        space.region_3d.view_rotation = camera.rotation_euler.to_quaternion()
        space.region_3d.view_location = center
        space.region_3d.view_distance = .75
        viewports.append(screen.name)
bpy.context.view_layer.update()
assert snapshot() == before, 'Unexpected model data mutation before save.'
bpy.ops.wm.save_as_mainfile(filepath=str(blend), check_existing=False)
bpy.ops.wm.open_mainfile(filepath=str(blend))
after = snapshot()
assert after == before, 'Saved/reopened model data differs from original verified file.'
assert glbs == {p.name: sha(p) for p in output.glob('*.glb')}, 'GLB changed.'
scene = bpy.data.scenes['Bilateral_Realistic_Review']
assert bpy.context.scene == scene and scene.cycles.samples == 24 and scene.cycles.use_denoising
report = {'status': 'passed', 'scope': 'Presentation settings only; no geometry, rig, pose, morph, weights, UV, material nodes or packed-image changes.',
          'backup': str(backup), 'before_blend_sha256': old_sha, 'after_blend_sha256': sha(blend),
          'glb_sha256_unchanged': glbs, 'before_settings': old_settings,
          'after_settings': {'scene': scene.name, 'camera': scene.camera.name,
                             'camera_world_matrix': value(scene.camera.matrix_world), 'orthographic_scale': .68,
                             'resolution': [1600, 1300], 'resolution_percentage': 100,
                             'samples': 24, 'denoising': True,
                             'matching_render': 'bilateral_dorsum.png',
                             'upperarms_hidden_for_framing': hidden_upperarms,
                             'viewport_screens': viewports, 'viewport_shading': 'MATERIAL',
                             'viewport_scene_lights_and_world': True, 'viewport_frame': 'CAMERA',
                             'viewport_overlays': False},
          'signature_method': 'Exact float buffers for mesh/UV/shape data; topology, deform groups, rest and pose matrices; material sockets and links; packed-image binary SHA256. Compared before, in memory after, and after save/reopen.',
          'before_signatures': before, 'after_signatures': after,
          'all_model_signatures_identical': True, 'render_not_repeated': True}
(output / 'review_setup_report.json').write_text(json.dumps(report, indent=2, ensure_ascii=False))
build = json.loads((output / 'build_report.json').read_text())
build['outputs'][blend.name] = {'bytes': blend.stat().st_size, 'sha256': sha(blend)}
build['delivery_review_setup'] = {'report': 'review_setup_report.json', 'status': 'passed',
                                  'model_signatures_unchanged': True, 'presentation_only': True}
(output / 'build_report.json').write_text(json.dumps(build, indent=2, ensure_ascii=False))
print('REALISM_REVIEW_SETUP_PASSED', sha(blend))
