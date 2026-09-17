"""Render actual supplied anatomy and its character attachment without saving.

Import inside Blender and call render_hands(scene, hands, out), where each hand
contains holder/body/nails/rig, then render_character(character_scene, out).
The functions return manifests and use transient evaluated meshes with the
source UVs, normals and materials. Source poses and the current scene are restored.

CLI: blender --background --threads 2 --python this.py -- --source final.blend
     --output-dir review --scope both --samples 16
No generated images, composites, retouching, material overrides or source saves.
"""
import argparse
import hashlib
import json
import math
import sys
from array import array
from pathlib import Path

import bpy
from mathutils import Matrix, Vector

DIGITS = ('thumb', 'index', 'middle', 'ring', 'little')
# Additional rotation from the supplied, already curled rest shape. Callers may
# pass their final runtime limits via the optional limits_degrees keyword.
DEFAULT_LIMITS_DEGREES = {
    'thumb': (25., 35., 45.), 'index': (60., 45., 45.),
    'middle': (60., 45., 45.), 'ring': (60., 45., 45.),
    'little': (60., 45., 45.),
}


def sha(path):
    digest = hashlib.sha256()
    with Path(path).open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(chunk)
    return digest.hexdigest()


def vec(v):
    return [float(x) for x in v]


def mat(m):
    return [vec(row) for row in m]


def descendants(obj):
    return [obj] + [child for item in obj.children for child in descendants(item)]


def geometry_signature(objects):
    """Hash source mesh positions, topology, UVs and shape-key coordinates."""
    result = {}
    for obj in objects:
        if obj.type != 'MESH':
            continue
        mesh = obj.data
        digest = hashlib.sha256()
        for collection, property_name, components, kind in (
            (mesh.vertices, 'co', 3, 'f'),
            (mesh.loops, 'vertex_index', 1, 'i'),
            (mesh.polygons, 'loop_total', 1, 'i'),
            (mesh.polygons, 'material_index', 1, 'i'),
        ):
            values = array(kind, [0]) * (len(collection) * components)
            collection.foreach_get(property_name, values)
            digest.update(values.tobytes())
        for layer in mesh.uv_layers:
            values = array('f', [0]) * (len(layer.data) * 2)
            layer.data.foreach_get('uv', values)
            digest.update(layer.name.encode()); digest.update(values.tobytes())
        if mesh.shape_keys:
            for key in mesh.shape_keys.key_blocks:
                values = array('f', [0]) * (len(key.data) * 3)
                key.data.foreach_get('co', values)
                digest.update(key.name.encode()); digest.update(values.tobytes())
        digest.update(json.dumps([m.name if m else None for m in mesh.materials]).encode())
        result[obj.name] = digest.hexdigest()
    return result


def _review_scene(width, height, samples, threads):
    scene = bpy.data.scenes.new('Supplied_Review_Transient')
    scene.render.engine = 'CYCLES'
    scene.cycles.device = 'CPU'
    scene.cycles.samples = samples
    scene.cycles.use_denoising = True
    scene.cycles.max_bounces = 6
    scene.render.threads_mode = 'FIXED'
    scene.render.threads = threads
    scene.render.resolution_x = width
    scene.render.resolution_y = height
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = 'PNG'
    scene.render.image_settings.color_mode = 'RGB'
    scene.render.film_transparent = False
    scene.view_settings.view_transform = 'AgX'
    scene.view_settings.look = 'AgX - Medium High Contrast'
    scene.view_settings.exposure = -.7
    world = bpy.data.worlds.new('Supplied_Review_Charcoal_Transient')
    world.use_nodes = True
    nodes = world.node_tree.nodes; links = world.node_tree.links
    nodes['Background'].inputs['Color'].default_value = (.08, .08, .08, 1)
    nodes['Background'].inputs['Strength'].default_value = .3
    visible = nodes.new('ShaderNodeBackground')
    visible.inputs['Color'].default_value = (.035, .035, .035, 1)
    visible.inputs['Strength'].default_value = 1
    ray = nodes.new('ShaderNodeLightPath')
    mix = nodes.new('ShaderNodeMixShader')
    links.new(ray.outputs['Is Camera Ray'], mix.inputs[0])
    links.new(nodes['Background'].outputs[0], mix.inputs[1])
    links.new(visible.outputs[0], mix.inputs[2])
    links.new(mix.outputs[0], nodes['World Output'].inputs['Surface'])
    scene.world = world
    return scene


def _cleanup(scene):
    world = scene.world
    for obj in list(scene.objects):
        data = obj.data; kind = obj.type
        bpy.data.objects.remove(obj, do_unlink=True)
        if data and data.users == 0:
            collection = {'MESH': bpy.data.meshes, 'LIGHT': bpy.data.lights,
                          'CAMERA': bpy.data.cameras}.get(kind)
            if collection is not None:
                collection.remove(data)
    bpy.data.scenes.remove(scene)
    if world and world.users == 0:
        bpy.data.worlds.remove(world)


def _copy_mesh(obj, review, dg, transform):
    mesh = bpy.data.meshes.new_from_object(obj.evaluated_get(dg),
        preserve_all_data_layers=True, depsgraph=dg)
    copy = bpy.data.objects.new('Review_' + obj.name, mesh)
    review.collection.objects.link(copy)
    copy.matrix_world = transform @ obj.matrix_world
    return copy


def _world_points(obj, predicate=None):
    return [obj.matrix_world @ v.co for v in obj.data.vertices
            if predicate is None or predicate(v.co)]


def _camera_frame(points, outward, up, width, height, margin=1.12):
    outward = Vector(outward).normalized()
    up = Vector(up); up = (up - outward * up.dot(outward)).normalized()
    right = up.cross(outward).normalized()
    axes = (right, up, outward)
    low = [min(p.dot(a) for p in points) for a in axes]
    high = [max(p.dot(a) for p in points) for a in axes]
    center = sum((a * ((lo + hi) / 2) for a, lo, hi in zip(axes, low, high)), Vector())
    aspect = width / height
    scale = max((high[1] - low[1]) * margin,
                (high[0] - low[0]) / aspect * margin) * max(1., aspect)
    scale = max(scale, .04)
    return center, right, up, outward, scale


def _render(review, points, outward, up, path, *, margin=1.12, lighting_span=.30):
    center, right, up, outward, scale = _camera_frame(points, outward, up,
        review.render.resolution_x, review.render.resolution_y, margin)
    transient = []
    camera_data = bpy.data.cameras.new('Supplied_Review_Camera_Transient')
    camera_data.type = 'ORTHO'; camera_data.ortho_scale = scale
    camera_data.clip_start = .001; camera_data.clip_end = 100
    camera = bpy.data.objects.new('Supplied_Review_Camera_Transient', camera_data)
    review.collection.objects.link(camera); transient.append(camera)
    rotation = Matrix((right, up, outward)).transposed().to_4x4()
    rotation.translation = center + outward * max(scale * 3, 1.)
    camera.matrix_world = rotation; review.camera = camera
    lighting = []
    # Distances, area and watts scale together, maintaining comparable exposure
    # between hands, wrist closeups and the full character without tinting skin.
    for label, offsets, watts, area in (
        ('Key', (-.8, .8, 1.), 9., 1.05),
        ('Fill', (1., .05, .8), 4., 1.25),
        ('Rim', (.6, .7, -.5), 6., .8),
    ):
        data = bpy.data.lights.new('Supplied_Review_' + label, 'AREA')
        data.shape = 'DISK'; data.size = area * lighting_span
        data.energy = watts * (lighting_span / .30) ** 2
        data.color = (1., 1., 1.)
        light = bpy.data.objects.new(data.name, data)
        review.collection.objects.link(light); transient.append(light)
        light.location = center + lighting_span * (right * offsets[0] + up * offsets[1] + outward * offsets[2])
        light.rotation_euler = (center - light.location).to_track_quat('-Z', 'Y').to_euler()
        lighting.append({'name': label, 'location': vec(light.location), 'watts': data.energy, 'size_m': data.size})
    try:
        review.render.filepath = str(path)
        bpy.ops.render.render(write_still=True, scene=review.name)
        return {'file': path.name, 'sha256': sha(path), 'actual_blender_geometry': True,
            'camera_center': vec(center), 'camera_outward': vec(outward),
            'camera_up': vec(up), 'ortho_scale_m': scale, 'lighting': lighting}
    finally:
        review.camera = None
        for obj in transient:
            data = obj.data; kind = obj.type
            bpy.data.objects.remove(obj, do_unlink=True)
            (bpy.data.cameras if kind == 'CAMERA' else bpy.data.lights).remove(data)


def _capture_pose(hands):
    return {side: {'bones': {p.name: p.matrix_basis.copy() for p in h['rig'].pose.bones},
        'keys': {k.name: k.value for k in h['body'].data.shape_keys.key_blocks}
            if h['body'].data.shape_keys else {}}
        for side, h in hands.items()}


def _restore_pose(hands, saved):
    for side, h in hands.items():
        for bone in h['rig'].pose.bones:
            bone.matrix_basis = saved[side]['bones'][bone.name]
        if h['body'].data.shape_keys:
            for key in h['body'].data.shape_keys.key_blocks:
                key.value = saved[side]['keys'][key.name]
    bpy.context.view_layer.update()


def _set_pose(hands, amount, limits):
    for h in hands.values():
        for bone in h['rig'].pose.bones:
            bone.matrix_basis = Matrix.Identity(4)
        if h['body'].data.shape_keys:
            for key in h['body'].data.shape_keys.key_blocks:
                key.value = 0.
        for digit in DIGITS:
            for joint in range(3):
                angle = amount * limits[digit][joint]
                h['rig'].pose.bones[digit + str(joint)].matrix_basis = Matrix.Rotation(-math.radians(angle), 4, 'X')
                if h['body'].data.shape_keys:
                    key = h['body'].data.shape_keys.key_blocks.get(f'Joint_{digit}_{joint}')
                    if key: key.value = amount
    bpy.context.view_layer.update()


def render_hands(scene, hands, out, *, samples=16, threads=2, width=1100,
                 height=1000, limits_degrees=None, fist_first=False):
    """Seven actual renders: two neutral, three oblique poses, two wrist details.

    Neutral/relaxed means zero ADDED bend and retains the source's inherent curl.
    Fist means simultaneous unit flex at the recorded additional limits; it is a
    diagnostic requested pose, not an assertion that every surface is contact safe.
    """
    assert bpy.app.background, 'Use hidden/background Blender for review'
    out = Path(out).resolve(); out.mkdir(parents=True, exist_ok=True)
    limits = limits_degrees or DEFAULT_LIMITS_DEGREES
    original_scene = bpy.context.window.scene
    bpy.context.window.scene = scene; bpy.context.view_layer.update()
    saved = _capture_pose(hands)
    objects = list({o for h in hands.values() for o in descendants(h['holder'])})
    before = geometry_signature(objects)
    report = {'status': 'rendering', 'renderer_sha256': sha(__file__),
        'engine': 'CYCLES', 'samples': samples, 'threads': threads,
        'width': width, 'height': height, 'exposure_stops': -.7, 'actual_materials': True,
        'additional_flex_limits_degrees': limits,
        'neutral_definition': 'Supplied anatomy with zero added bone rotations; original source curl retained.',
        'source_geometry_sha256': before, 'renders': {}}
    try:
        poses = [('fist', 1.), ('neutral', 0.)] if fist_first else [('neutral', 0.), ('fist', 1.)]
        for pose, amount in poses:
            _set_pose(hands, amount, limits)
            dg = bpy.context.evaluated_depsgraph_get()
            review = _review_scene(width, height, samples, threads)
            try:
                # Measure the actual deformed body before translating the review
                # copies. Only translations change the canonical hand placement.
                native_bounds = {}
                for side, h in hands.items():
                    body = h['body'].evaluated_get(dg); mesh = body.to_mesh()
                    native = h['holder'].matrix_world.inverted() @ h['body'].matrix_world
                    points = [native @ v.co for v in mesh.vertices]
                    native_bounds[side] = (min(p.x for p in points), max(p.x for p in points))
                    body.to_mesh_clear()
                total_width = sum(hi - lo for lo, hi in native_bounds.values())
                cursor = -(total_width + .035) / 2
                display = {}; frame_points = []
                for side in ('left', 'right'):
                    h = hands[side]; low, high = native_bounds[side]
                    shift = cursor - low; cursor += high - low + .035
                    native = Matrix.Translation((shift, 0, 0)) @ h['holder'].matrix_world.inverted()
                    display[side] = {}
                    for obj in descendants(h['holder']):
                        if obj.type != 'MESH' or obj.hide_render: continue
                        duplicate = _copy_mesh(obj, review, dg, native)
                        if obj == h['body']: display[side]['body'] = duplicate
                    pts = _world_points(display[side]['body'])
                    frame_points.extend(pts)
                    # Include the real sleeve continuation below the capped wrist.
                    # Keep the complete fitted cuff in view even after the
                    # concealed skin stump is shortened into the fixed rim.
                    lower_y = min(min(p.y for p in pts) - .03, -.095)
                    lo = Vector((min(p.x for p in pts), lower_y, min(p.z for p in pts)))
                    hi = Vector((max(p.x for p in pts), lower_y, max(p.z for p in pts)))
                    frame_points.extend((lo, hi))
                views = [('hands_three_quarter_fist', (.45, -.5, 1.), (0, 1, 0)),
                         ('hands_palmar_fist', (.25, -.35, -1.), (0, 1, 0))]
                if pose == 'neutral':
                    views = [('hands_dorsal_neutral', (0, 0, 1), (0, 1, 0)),
                             ('hands_palmar_neutral', (0, 0, -1), (0, 1, 0)),
                             ('hands_three_quarter_relaxed', (.45, -.5, 1.), (0, 1, 0))]
                for name, outward, up in views:
                    report['renders'][name] = _render(review, frame_points, outward, up, out / (name + '.png'))
                    report['renders'][name]['additional_flex_amount'] = amount
                    (out / 'hands_render_report.json').write_text(json.dumps(report, indent=2))
                if pose == 'neutral':
                    for side, parts in display.items():
                        body = parts['body']
                        # Mesh local coordinates remain canonical in the final
                        # build. Crop with world-invariant native y through cuffs.
                        native_points = [body.matrix_world @ v.co for v in body.data.vertices
                                         if -.07 <= v.co.y <= .015]
                        assert native_points, 'No wrist region in canonical hand'
                        native_points += [p - Vector((0, .018, 0)) for p in native_points[::max(1, len(native_points)//40)]]
                        native_points += [Vector((p.x, -.09, p.z)) for p in native_points[::max(1, len(native_points)//40)]]
                        sign = 1 if side == 'left' else -1
                        name = 'wrist_' + side + '_dorsal'
                        report['renders'][name] = _render(review, native_points,
                            (.30 * sign, -.25, 1), (0, 1, 0), out / (name + '.png'), margin=1.25)
                        (out / 'hands_render_report.json').write_text(json.dumps(report, indent=2))
            finally:
                _cleanup(review)
        report['status'] = 'complete'
    finally:
        bpy.context.window.scene = scene
        _restore_pose(hands, saved)
        after = geometry_signature(objects)
        assert after == before, 'Review changed source mesh data'
        maximum = max(abs(h['rig'].pose.bones[name].matrix_basis[r][c] - basis[r][c])
            for side, h in hands.items() for name, basis in saved[side]['bones'].items()
            for r in range(4) for c in range(4))
        assert maximum < 1e-6, 'Source bone pose was not restored'
        report['source_geometry_unchanged'] = True
        report['source_pose_restore_maximum_matrix_error'] = maximum
        report['source_camera_and_render_settings_untouched'] = True
        (out / 'hands_render_report.json').write_text(json.dumps(report, indent=2))
        bpy.context.window.scene = original_scene
    return report


def render_character(scene, out, *, samples=16, threads=2, width=1000, height=1100):
    """Full character front plus actual left/right hand-to-bracer closeups."""
    assert bpy.app.background, 'Use hidden/background Blender for review'
    out = Path(out).resolve(); out.mkdir(parents=True, exist_ok=True)
    original_scene = bpy.context.window.scene
    bpy.context.window.scene = scene; bpy.context.view_layer.update()
    root = next(o for o in scene.objects if o.type == 'EMPTY' and o.name.startswith('GraveboundPlayer'))
    sources = [o for o in descendants(root) if o.type == 'MESH' and not o.hide_render]
    before = geometry_signature(sources)
    review = _review_scene(width, height, samples, threads)
    report = {'status': 'rendering', 'renderer_sha256': sha(__file__),
        'engine': 'CYCLES', 'samples': samples, 'threads': threads,
        'width': width, 'height': height, 'exposure_stops': -.7, 'actual_materials': True,
        'source_geometry_sha256': before, 'renders': {}}
    try:
        dg = bpy.context.evaluated_depsgraph_get()
        copies = {o.name: _copy_mesh(o, review, dg, Matrix.Identity(4)) for o in sources}
        points = [p for obj in copies.values() for p in _world_points(obj)]
        outward = root.matrix_world.to_3x3() @ Vector((0, -1, 0))
        up = root.matrix_world.to_3x3() @ Vector((0, 0, 1))
        name = 'character_front'
        report['renders'][name] = _render(review, points, outward, up, out / (name + '.png'), lighting_span=1.8)
        (out / 'character_render_report.json').write_text(json.dumps(report, indent=2))
        for side, suffix in [('left', 'R'), ('right', 'L')]:
            body = next(obj for name, obj in copies.items() if name.startswith('Gravebound_SuppliedHand_' + suffix))
            selected = _world_points(body, lambda p: -.07 <= p.y <= .025)
            assert selected, 'No character hand wrist region'
            native = body.matrix_world.to_3x3()
            selected += [p - native @ Vector((0, .025, 0)) for p in selected[::max(1, len(selected)//50)]]
            name = 'character_wrist_' + side
            report['renders'][name] = _render(review, selected,
                native @ Vector((.35 if side == 'left' else -.35, -.2, 1)),
                native @ Vector((0, 1, 0)), out / (name + '.png'), margin=1.25)
            (out / 'character_render_report.json').write_text(json.dumps(report, indent=2))
        report.update(status='complete', source_geometry_unchanged=geometry_signature(sources) == before,
                      source_camera_and_render_settings_untouched=True)
        assert report['source_geometry_unchanged']
    finally:
        _cleanup(review)
        bpy.context.window.scene = original_scene
        (out / 'character_render_report.json').write_text(json.dumps(report, indent=2))
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--output-dir', type=Path, required=True)
    parser.add_argument('--scope', choices=('hands', 'character', 'both'), default='both')
    parser.add_argument('--samples', type=int, default=16)
    parser.add_argument('--threads', type=int, default=2)
    parser.add_argument('--fist-first', action='store_true', help='Render both maximum-flex checks before neutral images')
    parser.add_argument('--limits-json', type=Path, help='Digit to three additional joint limits in degrees')
    args = parser.parse_args(sys.argv[sys.argv.index('--') + 1:])
    assert min(args.samples, args.threads) > 0
    original = sha(args.source)
    bpy.ops.wm.open_mainfile(filepath=str(args.source.resolve()))
    if args.scope in ('hands', 'both'):
        scene = bpy.data.scenes['Bilateral_SuppliedHands_Review']
        hands = {side: {'holder': scene.objects[side.upper() + '_PreviewTranslationOnly'],
            'body': scene.objects['Supplied_AnatomicalHand_' + side],
            'rig': scene.objects['Supplied_HandRig_' + side],
            'nails': {d: scene.objects['Nail_' + d + '_' + side] for d in DIGITS}}
            for side in ('left', 'right')}
        limits = json.loads(args.limits_json.read_text()) if args.limits_json else None
        render_hands(scene, hands, args.output_dir, samples=args.samples,
                     threads=args.threads, limits_degrees=limits, fist_first=args.fist_first)
    if args.scope in ('character', 'both'):
        render_character(bpy.data.scenes['Character_SuppliedHands_Review'], args.output_dir,
                         samples=args.samples, threads=args.threads)
    assert sha(args.source) == original, 'Source blend bytes changed'
    (args.output_dir / 'source_unchanged.json').write_text(json.dumps({
        'source': str(args.source.resolve()), 'sha256_before_and_after': original,
        'source_file_unchanged': True, 'renderer_sha256': sha(__file__)}, indent=2))
    print('SUPPLIED_REVIEW_COMPLETE', args.output_dir, flush=True)


if __name__ == '__main__':
    main()
