"""Inspect and render the actual downloaded Labrador without editing its source."""
import argparse
import hashlib
import json
import sys
from pathlib import Path

import bpy
from mathutils import Vector


def values(value):
    return list(value)


def matrix(value):
    return [list(row) for row in value]


def inspect(base):
    source = base/'source/LabradorDog_kenchoo_2k.glb'
    original_hash = hashlib.sha256(source.read_bytes()).hexdigest()
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(source))
    scene = bpy.context.scene
    rigs = [o for o in scene.objects if o.type == 'ARMATURE']
    if len(rigs) != 1:
        raise RuntimeError(f'Expected one actual Labrador armature, found {len(rigs)}')
    rig = rigs[0]
    meshes = [o for o in scene.objects if o.type == 'MESH' and not o.hide_render]
    scene.frame_set(1); bpy.context.view_layer.update()
    report = {'source': str(source.relative_to(base)), 'sha256': original_hash,
              'blender': bpy.app.version_string, 'rig': {'name': rig.name, 'matrix_world': matrix(rig.matrix_world)},
              'objects': [{'name': o.name, 'type': o.type, 'parent': o.parent.name if o.parent else None,
                           'matrix_world': matrix(o.matrix_world)} for o in scene.objects],
              'bones': [], 'meshes': [], 'actions': [], 'materials': [], 'images': []}
    for bone in rig.data.bones:
        report['bones'].append({'name': bone.name, 'parent': bone.parent.name if bone.parent else None,
                               'use_deform': bone.use_deform, 'head_local': values(bone.head_local),
                               'tail_local': values(bone.tail_local), 'matrix_local': matrix(bone.matrix_local),
                               'pose_matrix_frame1': matrix(rig.pose.bones[bone.name].matrix),
                               'constraints': [c.type for c in rig.pose.bones[bone.name].constraints]})
    all_points = []
    for mesh in meshes:
        points = [mesh.matrix_world @ vertex.co for vertex in mesh.data.vertices]
        all_points.extend(points)
        weights = {}
        for group in mesh.vertex_groups:
            vertices = [(vertex, element.weight) for vertex in mesh.data.vertices for element in vertex.groups if element.group == group.index]
            if not vertices:
                continue
            total = sum(weight for vertex, weight in vertices)
            center = sum(((mesh.matrix_world @ vertex.co)*weight for vertex, weight in vertices), Vector((0,0,0)))/total
            strong = [mesh.matrix_world @ vertex.co for vertex, weight in vertices if weight > .4]
            weights[group.name] = {'vertices': len(vertices), 'total_weight': total,
                                   'weighted_centroid_world': values(center),
                                   'strong_vertices': len(strong),
                                   'strong_bounds': [[min(p[axis] for p in strong), max(p[axis] for p in strong)] for axis in range(3)] if strong else None}
        report['meshes'].append({'name': mesh.name, 'vertices': len(mesh.data.vertices),
                                 'triangles': sum(len(poly.vertices)-2 for poly in mesh.data.polygons),
                                 'matrix_world': matrix(mesh.matrix_world),
                                 'modifiers': [{'type': modifier.type, 'name': modifier.name,
                                                'object': modifier.object.name if modifier.type == 'ARMATURE' and modifier.object else None}
                                               for modifier in mesh.modifiers],
                                 'shape_keys': [key.name for key in mesh.data.shape_keys.key_blocks] if mesh.data.shape_keys else [],
                                 'materials': [material.name for material in mesh.data.materials], 'weights': weights})
    for action in bpy.data.actions:
        channels = []
        for layer in action.layers:
            for strip in layer.strips:
                for bag in strip.channelbags:
                    channels.extend(curve.data_path for curve in bag.fcurves)
        report['actions'].append({'name': action.name, 'frames': values(action.frame_range),
                                  'channels': sorted(set(channels)), 'slots': [slot.identifier for slot in action.slots]})
    for material in bpy.data.materials:
        report['materials'].append({'name': material.name,
                                   'nodes': [{'name': node.name, 'type': node.type,
                                              'image': node.image.name if node.type == 'TEX_IMAGE' and node.image else None}
                                             for node in material.node_tree.nodes] if material.use_nodes else []})
    for image in bpy.data.images:
        report['images'].append({'name': image.name, 'size': values(image.size), 'colorspace': image.colorspace_settings.name})
    low = Vector(tuple(min(p[i] for p in all_points) for i in range(3)))
    high = Vector(tuple(max(p[i] for p in all_points) for i in range(3)))
    report['bounds_world_m'] = {'min': values(low), 'max': values(high), 'size': values(high-low)}
    report_path = base/'rig-inspection.json'
    report_path.write_text(json.dumps(report, indent=2)+'\n')
    # Inspection scene is never saved back over the licensed GLB.
    scene.render.engine = 'BLENDER_EEVEE'; scene.eevee.taa_render_samples = 8
    scene.render.resolution_x = 900; scene.render.resolution_y = 650; scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = 'PNG'
    scene.view_settings.view_transform = 'AgX'
    scene.world = bpy.data.worlds.new('LabradorInspectionWorld'); scene.world.use_nodes = True
    scene.world.node_tree.nodes['Background'].inputs['Color'].default_value = (.12,.17,.24,1)
    scene.world.node_tree.nodes['Background'].inputs['Strength'].default_value = .45
    size = max(high-low); center = (high+low)*.5
    bpy.ops.mesh.primitive_plane_add(size=10*size, location=(center.x, center.y, low.z-.002))
    floor = bpy.context.object; material = bpy.data.materials.new('InspectionFloor'); material.use_nodes = True
    shader = material.node_tree.nodes.get('Principled BSDF'); shader.inputs['Base Color'].default_value = (.045,.06,.09,1)
    shader.inputs['Roughness'].default_value = .75; floor.data.materials.append(material)
    for offset,energy in [((1.3,-1.1,2),200),((-1.5,-.7,1.5),100),((.2,1.8,1.7),160)]:
        bpy.ops.object.light_add(type='AREA',location=center+Vector(offset)*size)
        light=bpy.context.object;light.data.energy=energy*size*size;light.data.size=2*size
        light.rotation_euler=(center-light.location).to_track_quat('-Z','Y').to_euler()
    bpy.ops.object.camera_add(); camera=bpy.context.object;scene.camera=camera
    camera.data.type='ORTHO';camera.data.ortho_scale=1.4*size
    output=base/'validation/rig';output.mkdir(parents=True,exist_ok=True)
    for name, offset in [('side',(2,.05,.4)),('three_quarter',(1.6,-1.7,.7)),('front',(0,-2,.45))]:
        camera.location=center+Vector(offset)*size
        camera.rotation_euler=(center-camera.location).to_track_quat('-Z','Y').to_euler()
        scene.render.filepath=str(output/(name+'.png'));bpy.ops.render.render(write_still=True)
    if hashlib.sha256(source.read_bytes()).hexdigest()!=original_hash:
        raise RuntimeError('Licensed source was modified')
    print('LABRADOR_RIG_INSPECTED',str(report_path),flush=True)


if __name__ == '__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--base',type=Path,required=True)
    args=parser.parse_args(sys.argv[sys.argv.index('--')+1:])
    inspect(args.base.resolve())
