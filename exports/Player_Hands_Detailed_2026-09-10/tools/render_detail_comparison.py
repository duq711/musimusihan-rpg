"""Render original greybox and refined left hand under identical lighting.

Fresh background process; imported inputs remain read-only, no scene is saved.
"""
import argparse
import hashlib
import json
import sys
from pathlib import Path

import bpy
from mathutils import Vector


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--greybox', type=Path, required=True)
    parser.add_argument('--detailed', type=Path, required=True)
    parser.add_argument('--output-dir', type=Path, required=True)
    args = parser.parse_args(sys.argv[sys.argv.index('--') + 1:])
    assert bpy.app.background, 'Background Blender required'
    output = args.output_dir.resolve()
    assert not output.exists() or not any(output.iterdir()), 'Refusing nonempty output directory'
    sources = [args.greybox.resolve(), args.detailed.resolve()]
    hashes = {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in sources}
    output.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    manifest = {'purpose': 'Identical camera, scale, exposure and lighting; modeled detail comparison',
                'source_sha256': hashes, 'renders': []}
    for path, offset, title in zip(sources, (-.17, .17), ('GREYBOX', 'DETAILED')):
        previous = set(scene.objects)
        bpy.ops.import_scene.gltf(filepath=str(path), bone_heuristic='TEMPERANCE')
        imported = set(scene.objects) - previous
        holder = bpy.data.objects.new(title + '_ReviewOffset', None)
        scene.collection.objects.link(holder)
        for obj in imported:
            if obj.parent is None:
                obj.parent = holder
        holder.location.x = offset
        text = bpy.data.curves.new(title + '_Label', 'FONT')
        text.body, text.align_x, text.size = title, 'CENTER', .018
        text.space_character = 1.12
        label = bpy.data.objects.new(title + '_Label', text)
        scene.collection.objects.link(label)
        label.location = (offset, -.142, .092)
        material = bpy.data.materials.new(title + '_LabelMaterial')
        material.diffuse_color = (.55, .55, .55, 1)
        material.use_nodes = True
        bsdf = material.node_tree.nodes.get('Principled BSDF')
        bsdf.inputs['Base Color'].default_value = (.55, .55, .55, 1)
        bsdf.inputs['Roughness'].default_value = .9
        text.materials.append(material)
    world = bpy.data.worlds.new('ComparisonWorld')
    world.use_nodes = True
    world.node_tree.nodes['Background'].inputs['Color'].default_value = (.055, .055, .055, 1)
    world.node_tree.nodes['Background'].inputs['Strength'].default_value = .4
    scene.world = world
    target = Vector((0, .04, 0))
    for name, position, power, size in (
            ('Key', (.35, -.15, .9), 32, .65),
            ('Fill', (-.55, .3, .55), 12, .6),
            ('Rim', (.15, .5, -.4), 18, .45)):
        data = bpy.data.lights.new(name, 'AREA')
        data.energy, data.shape, data.size = power, 'DISK', size
        lamp = bpy.data.objects.new(name, data)
        scene.collection.objects.link(lamp)
        lamp.location = position
        lamp.rotation_euler = (target - lamp.location).to_track_quat('-Z', 'Y').to_euler()
    data = bpy.data.cameras.new('ComparisonCamera')
    camera = bpy.data.objects.new('ComparisonCamera', data)
    scene.collection.objects.link(camera)
    camera.location = (0, .04, 2)
    camera.rotation_euler = (target - camera.location).to_track_quat('-Z', 'Y').to_euler()
    data.type, data.ortho_scale, data.clip_start = 'ORTHO', .67, .001
    scene.camera = camera
    scene.render.engine = 'CYCLES'
    scene.cycles.device, scene.cycles.samples = 'CPU', 32
    scene.render.resolution_x, scene.render.resolution_y = 1600, 1100
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = 'PNG'
    scene.render.filepath = str(output / 'greybox_to_detailed.png')
    bpy.ops.render.render(write_still=True)
    png = Path(scene.render.filepath)
    manifest['renders'].append({'file': png.name, 'sha256': hashlib.sha256(png.read_bytes()).hexdigest()})
    assert hashes == {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in sources}, 'Source changed'
    (output / 'comparison_manifest.json').write_text(json.dumps(manifest, indent=2), encoding='utf-8')
    print('DETAILED_COMPARISON_COMPLETE', output)


if __name__ == '__main__':
    main()
