"""Read-only signatures for a metadata-only wrist transition update."""
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
            'weights': 'compared separately under the approved wrist-weight formula',
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
               'custom_properties': value({k:v for k,v in obj.items() if k != 'wrist_flex_start_z'}),
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
                       'filepath': i.filepath, 'packed': [hashlib.sha256(p.packed_file.data).hexdigest() for p in i.packed_files]}
              for i in bpy.data.images if i.type != 'RENDER_RESULT'}
    return {'meshes': {k: hashed(v) for k, v in meshes.items()},
            'objects': {k: hashed(v) for k, v in objects.items()},
            'materials': {k: hashed(v) for k, v in materials.items()}, 'images': images, 'presentation': presentation_snapshot()}



def presentation_snapshot():
    cameras={o.name: {'basis':value(o.matrix_basis),'parent_inverse':value(o.matrix_parent_inverse),'parent':o.parent.name if o.parent else None,
        'type':o.data.type,'lens':o.data.lens,'ortho_scale':o.data.ortho_scale,'clip_start':o.data.clip_start,'clip_end':o.data.clip_end,
        'shift_x':o.data.shift_x,'shift_y':o.data.shift_y,'hide_render':o.hide_render} for o in bpy.data.objects if o.type=='CAMERA'}
    scenes={s.name:{'camera':s.camera.name if s.camera else None,'world':s.world.name if s.world else None,
        'render':[s.render.engine,s.render.resolution_x,s.render.resolution_y,s.render.resolution_percentage,s.render.filepath,s.render.film_transparent],
        'cycles':[s.cycles.samples,s.cycles.use_denoising,s.cycles.device],
        'view':[s.view_settings.view_transform,s.view_settings.look,s.view_settings.exposure,s.view_settings.gamma]} for s in bpy.data.scenes}
    viewport={s.name:[{'shading':a.spaces.active.shading.type,'perspective':a.spaces.active.region_3d.view_perspective,
        'view_rotation':value(a.spaces.active.region_3d.view_rotation),'view_location':value(a.spaces.active.region_3d.view_location),
        'view_distance':a.spaces.active.region_3d.view_distance,'camera_zoom':a.spaces.active.region_3d.view_camera_zoom,
        'camera_offset':value(a.spaces.active.region_3d.view_camera_offset)} for a in s.areas if a.type=='VIEW_3D'] for s in bpy.data.screens}
    lights={o.name:{'type':o.data.type,'energy':o.data.energy,'color':value(o.data.color),'size':getattr(o.data,'size',None),'shape':getattr(o.data,'shape',None),'visibility':[o.hide_render,o.hide_viewport]} for o in bpy.data.objects if o.type=='LIGHT'}
    worlds={w.name:{'color':value(w.color),'use_nodes':w.use_nodes,'nodes':{n.name:{'type':n.bl_idname,'inputs':[(v.name,value(getattr(v,'default_value',None))) for v in n.inputs]} for n in w.node_tree.nodes} if w.node_tree else None,'links':[(l.from_node.name,l.from_socket.identifier,l.to_node.name,l.to_socket.identifier) for l in w.node_tree.links] if w.node_tree else None} for w in bpy.data.worlds}
    return {'cameras':cameras,'scenes':scenes,'viewports':viewport,'lights':lights,'worlds':worlds,'active_scene':bpy.context.scene.name}
