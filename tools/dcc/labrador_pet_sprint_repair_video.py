"""Render the foreleg-corrected sprint at normal and half speed on Mac Blender."""
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

FPS = 30
SHOTS = [('side', 1.0), ('side', .5), ('quarter', 1.0)]


def render(base, extended, collected):
    production = base / 'production/LabradorPet_SprintRepair.blend'
    source_sha = hashlib.sha256(production.read_bytes()).hexdigest()
    bpy.ops.wm.open_mainfile(filepath=str(production))
    manifest = json.loads((base / 'export/sprint-repair-manifest.json').read_text())
    spec = next(c for c in manifest['clips'] if c['name'] == 'Run')
    rig = bpy.data.objects['LabradorPet']
    scene = bpy.context.scene
    original = bpy.data.actions['Run']
    start, end = spec['frames']
    speed = spec['speed_m_s']
    reel = bpy.data.actions.new('Preview_ReferenceSprint')
    timeline = []
    frame = 1
    for view, rate in SHOTS:
        count = FPS * 4
        timeline.append({'clip': 'Run', 'view': view, 'playback_rate': rate,
                         'first_frame': frame, 'last_frame': frame + count - 1,
                         'nominal_speed_m_s': speed, 'ground_speed_m_s': speed * rate})
        for i in range(count):
            source_frame = start + (i / FPS * manifest['fps'] * rate) % (end - start)
            set_action(rig, original)
            scene.frame_set(math.floor(source_frame), subframe=source_frame % 1)
            bpy.context.view_layer.update()
            pose = {b.name: b.matrix_basis.copy() for b in rig.pose.bones}
            set_action(rig, None)
            scene.frame_set(frame)
            for bone in rig.pose.bones:
                bone.matrix_basis = pose[bone.name]
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
    camera.data.ortho_scale = 2.30
    scene.render.resolution_x = 960
    scene.render.resolution_y = 640
    scene.render.fps = FPS
    line_material = bpy.data.materials.new('SprintGroundLines')
    line_material.diffuse_color = (.17, .19, .22, 1)
    curve = bpy.data.curves.new('SprintGroundGrid', 'CURVE')
    curve.dimensions = '3D'
    curve.bevel_depth = .00055
    curve.bevel_resolution = 0
    for i in range(-40, 41):
        for axis in ('x', 'y'):
            spline = curve.splines.new('POLY')
            spline.points.add(1)
            for j, endpoint in enumerate((-10, 10)):
                spline.points[j].co = (i * .25, endpoint, 0, 1) if axis == 'x' else (endpoint, i * .25, 0, 1)
    grid = bpy.data.objects.new('SprintGroundGrid', curve)
    scene.collection.objects.link(grid)
    grid.location.z = .0005
    curve.materials.append(line_material)
    font = bpy.data.fonts.load('/System/Library/Fonts/AppleSDGothicNeo.ttc')
    material = bpy.data.materials.new('SprintCaption')
    material.use_nodes = True
    material.node_tree.nodes.clear()
    shader = material.node_tree.nodes.new('ShaderNodeEmission')
    shader.inputs['Color'].default_value = (.022, .030, .044, 1)
    output_node = material.node_tree.nodes.new('ShaderNodeOutputMaterial')
    material.node_tree.links.new(shader.outputs[0], output_node.inputs['Surface'])
    def caption(name, text, y):
        data = bpy.data.curves.new(name, 'FONT')
        data.body = text
        data.font = font
        data.size = .037
        data.align_x = 'CENTER'
        data.align_y = 'CENTER'
        obj = bpy.data.objects.new(name, data)
        scene.collection.objects.link(obj)
        obj.parent = camera
        obj.location = (0, y, -1)
        data.materials.append(material)
        obj.visible_shadow = False
        return obj
    caption('SprintTitle', '래브라도 · 영상 기준 질주 / Labrador sprint', .63)
    label = caption('SprintLabel', '', -.65)
    def update(current_scene, *unused):
        shot = next((s for s in timeline if s['first_frame'] <= current_scene.frame_current <= s['last_frame']), timeline[-1])
        rate = shot['playback_rate']
        label.data.body = ('보통 속도 / Normal' if rate == 1 else '0.5배속 / Half speed') + f' · {speed:.2f} m/s'
        camera.location = (2.2, .04, .68) if shot['view'] == 'side' else (1.8, -1.95, 1.10)
        camera.rotation_euler = (Vector((0, .025, .45)) - camera.location).to_track_quat('-Z', 'Y').to_euler()
        grid.location.y = ((current_scene.frame_current - shot['first_frame']) / FPS * speed * rate) % .25
    bpy.app.handlers.frame_change_pre.append(update)
    scene.frame_start = 1
    scene.frame_end = frame - 1
    for name, phase in [('Extended', extended), ('Collected', collected)]:
        set_action(rig, original)
        poster_frame = start + phase * (end - start)
        scene.frame_set(math.floor(poster_frame), subframe=poster_frame % 1)
        scene.render.filepath = str(base / f'export/LabradorPet_SprintRepair_{name}.png')
        bpy.ops.render.render(write_still=True)
    set_action(rig, reel)
    scene.frame_set(1)
    raw = base / 'export/LabradorPet_SprintRepair_Render.mp4'
    scene.render.image_settings.media_type = 'VIDEO'
    scene.render.image_settings.file_format = 'FFMPEG'
    scene.render.ffmpeg.format = 'MPEG4'
    scene.render.ffmpeg.codec = 'H264'
    scene.render.ffmpeg.constant_rate_factor = 'HIGH'
    scene.render.ffmpeg.ffmpeg_preset = 'GOOD'
    scene.render.ffmpeg.gopsize = FPS
    scene.render.ffmpeg.audio_codec = 'NONE'
    scene.render.filepath = str(raw)
    print('LABRADOR_SPRINT_REEL_BEGIN', frame - 1, flush=True)
    bpy.ops.render.render(animation=True)
    if not raw.exists():
        candidates = list(raw.parent.glob('LabradorPet_SprintRepair_Render*.mp4'))
        if len(candidates) != 1:
            raise RuntimeError('Cannot identify rendered reel')
        candidates[0].replace(raw)
    output = base / 'export/LabradorPet_SprintRepair.mp4'
    streaming = faststart(raw, output)
    raw.unlink()
    assert hashlib.sha256(production.read_bytes()).hexdigest() == source_sha
    summary = {'file': str(output.relative_to(base)), 'width': 960, 'height': 640,
               'fps': FPS, 'frames': frame - 1, 'duration_seconds': (frame - 1) / FPS,
               'bytes': output.stat().st_size, 'sha256': hashlib.sha256(output.read_bytes()).hexdigest(),
               'source_sha256': source_sha, 'source_unchanged': True, 'timeline': timeline,
               'streaming': streaming, 'poster_phases': {'Extended': extended, 'Collected': collected},
               'scope': 'Actual corrected Run poses at normal and half speed. Moving ground matches the declared nominal speed and playback rate.'}
    (base / 'repair-video-summary.json').write_text(json.dumps(summary, ensure_ascii=False, indent=2) + '\n')
    print('LABRADOR_SPRINT_REEL_COMPLETE', output, flush=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--base', type=Path, required=True)
    parser.add_argument('--extended-phase', type=float, default=.2)
    parser.add_argument('--collected-phase', type=float, default=.7)
    args = parser.parse_args(sys.argv[sys.argv.index('--') + 1:])
    render(args.base.resolve(), args.extended_phase, args.collected_phase)
