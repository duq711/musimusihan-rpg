"""Render the final Labrador Walk/Run cycles, with a speed-matched ground grid."""
import argparse
import hashlib
import json
import math
import sys
from pathlib import Path

import bpy
from mathutils import Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
from labrador_pet import channels, set_action
from labrador_pet_preview import stage
from mp4_faststart import faststart

FPS = 24
SHOTS = [('Walk', 'side'), ('Walk', 'quarter'), ('Run', 'side'), ('Run', 'quarter')]
SHOT_SECONDS = 3


def render(base):
    production = base / 'production/LabradorPet_Locomotion.blend'
    source_sha = hashlib.sha256(production.read_bytes()).hexdigest()
    bpy.ops.wm.open_mainfile(filepath=str(production))
    manifest = json.loads((base / 'export/locomotion-manifest.json').read_text())
    specs = {c['name']: c for c in manifest['clips']}
    rig = bpy.data.objects['LabradorPet']
    scene = bpy.context.scene
    reel = bpy.data.actions.new('Preview_LabradorLocomotion')
    timeline = []
    frame = 1
    for name, view in SHOTS:
        spec = specs[name]
        source = bpy.data.actions[name]
        start, end = spec['frames']
        count = FPS * SHOT_SECONDS
        speed = spec.get('speed_m_s', spec.get('nominal_speed_m_s', 0))
        if speed <= 0:
            raise RuntimeError('Speed-matched preview requires a positive measured speed')
        timeline.append({'clip': name, 'view': view, 'first_frame': frame,
                         'last_frame': frame + count - 1, 'speed_m_s': speed})
        for i in range(count):
            source_frame = start + (i / FPS * manifest['fps']) % (end - start)
            set_action(rig, source)
            scene.frame_set(math.floor(source_frame), subframe=source_frame % 1)
            bpy.context.view_layer.update()
            matrices = {b.name: b.matrix_basis.copy() for b in rig.pose.bones}
            set_action(rig, None)
            scene.frame_set(frame)
            for bone in rig.pose.bones:
                bone.matrix_basis = matrices[bone.name]
            set_action(rig, reel)
            for bone in rig.pose.bones:
                for channel in ('location', 'rotation_quaternion', 'scale'):
                    bone.keyframe_insert(channel, frame=frame, group=bone.name)
            frame += 1
    for curve in channels(reel):
        for key in curve.keyframe_points:
            key.interpolation = 'LINEAR'
    set_action(rig, reel)
    camera = stage(scene)
    camera.data.ortho_scale = 2.35
    scene.render.resolution_x = 960
    scene.render.resolution_y = 640
    scene.render.fps = FPS
    line_material = bpy.data.materials.new('LocomotionGroundLines')
    line_material.diffuse_color = (.17, .19, .22, 1)
    curve = bpy.data.curves.new('LocomotionGroundGrid', 'CURVE')
    curve.dimensions = '3D'
    curve.bevel_depth = .00055
    curve.bevel_resolution = 0
    for i in range(-40, 41):
        for axis in ('x', 'y'):
            spline = curve.splines.new('POLY')
            spline.points.add(1)
            for j, end in enumerate((-10, 10)):
                spline.points[j].co = (i * .25, end, 0, 1) if axis == 'x' else (end, i * .25, 0, 1)
    grid = bpy.data.objects.new('LocomotionGroundGrid', curve)
    scene.collection.objects.link(grid)
    grid.location.z = .0005
    curve.materials.append(line_material)
    font = bpy.data.fonts.load('/System/Library/Fonts/AppleSDGothicNeo.ttc')
    material = bpy.data.materials.new('LocomotionCaption')
    material.use_nodes = True
    material.node_tree.nodes.clear()
    shader = material.node_tree.nodes.new('ShaderNodeEmission')
    shader.inputs['Color'].default_value = (.022, .030, .044, 1)
    shader.inputs['Strength'].default_value = 1
    output_node = material.node_tree.nodes.new('ShaderNodeOutputMaterial')
    material.node_tree.links.new(shader.outputs[0], output_node.inputs['Surface'])
    def caption(name, body, y):
        data = bpy.data.curves.new(name, 'FONT')
        data.body = body; data.font = font; data.size = .041
        data.align_x = 'CENTER'; data.align_y = 'CENTER'
        obj = bpy.data.objects.new(name, data); scene.collection.objects.link(obj)
        obj.parent = camera; obj.location = (0, y, -1)
        data.materials.append(material); obj.visible_shadow = False
        return obj
    caption('LocomotionTitle', '래브라도 · 걷기와 달리기 / Labrador locomotion', .65)
    label = caption('LocomotionLabel', '', -.66)
    def update(scene, *unused):
        shot = next((s for s in timeline if s['first_frame'] <= scene.frame_current <= s['last_frame']), timeline[-1])
        name = '걷기 / Walk' if shot['clip'] == 'Walk' else '달리기 / Run'
        label.data.body = f"{name} · {shot['speed_m_s']:.2f} m/s"
        camera.location = (1.8, .1, .80) if shot['view'] == 'side' else (1.6, -1.85, 1.05)
        camera.rotation_euler = (Vector((0, .03, .49)) - camera.location).to_track_quat('-Z', 'Y').to_euler()
        grid.location.y = ((scene.frame_current - shot['first_frame']) / FPS * shot['speed_m_s']) % .25
    bpy.app.handlers.frame_change_pre.append(update)
    scene.frame_start = 1; scene.frame_end = frame - 1
    for name, poster_frame in [('Walk', 80), ('Run', 224)]:
        scene.frame_set(poster_frame)
        scene.render.filepath = str(base / f'export/LabradorPet_{name}.png')
        bpy.ops.render.render(write_still=True)
    scene.frame_set(1)
    raw = base / 'export/LabradorPet_Locomotion_Render.mp4'
    scene.render.image_settings.media_type = 'VIDEO'
    scene.render.image_settings.file_format = 'FFMPEG'
    scene.render.ffmpeg.format = 'MPEG4'; scene.render.ffmpeg.codec = 'H264'
    scene.render.ffmpeg.constant_rate_factor = 'HIGH'; scene.render.ffmpeg.ffmpeg_preset = 'GOOD'
    scene.render.ffmpeg.gopsize = FPS; scene.render.ffmpeg.audio_codec = 'NONE'
    scene.render.filepath = str(raw)
    print('LABRADOR_LOCOMOTION_REEL_BEGIN', frame - 1, flush=True)
    bpy.ops.render.render(animation=True)
    if not raw.exists():
        candidates = list(raw.parent.glob('LabradorPet_Locomotion_Render*.mp4'))
        if len(candidates) != 1:
            raise RuntimeError('Cannot identify rendered video')
        candidates[0].replace(raw)
    output = base / 'export/LabradorPet_Locomotion.mp4'
    streaming = faststart(raw, output); raw.unlink()
    if hashlib.sha256(production.read_bytes()).hexdigest() != source_sha:
        raise RuntimeError('Production changed during video rendering')
    summary = {'file': str(output.relative_to(base)), 'width': 960, 'height': 640,
               'fps': FPS, 'frames': frame - 1, 'duration_seconds': (frame - 1) / FPS,
               'bytes': output.stat().st_size, 'sha256': hashlib.sha256(output.read_bytes()).hexdigest(),
               'source_unchanged': True, 'timeline': timeline, 'streaming': streaming,
               'scope': 'Actual Walk/Run skeleton clips with nominal-speed moving ground, side and three-quarter views.'}
    (base / 'locomotion-video-summary.json').write_text(json.dumps(summary, ensure_ascii=False, indent=2) + '\n')
    print('LABRADOR_LOCOMOTION_REEL_COMPLETE', output, flush=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--base', type=Path, required=True)
    args = parser.parse_args(sys.argv[sys.argv.index('--') + 1:])
    render(args.base.resolve())
