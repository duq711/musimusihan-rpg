"""Render the delivered Labrador standing clips as a seekable final video.

The reel shows the original idle and calm petting base. Mouse-driven head,
ear, eyelid and coat reactions are demonstrated by the interactive preview.
"""
import argparse
import hashlib
import json
import sys
from pathlib import Path

import bpy
from mathutils import Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
from labrador_pet import channels, set_action
from labrador_pet_preview import stage
from mp4_faststart import faststart

FPS = 24
SHOTS = [('IdleFriendly', 1, '원본 대기 / Original idle', 'threequarter'),
         ('PetEnjoy', 2, '쓰다듬기 기본 자세 / Calm petting base', 'side')]


def bake(rig, manifest):
    scene = bpy.context.scene
    specs = {row['name']: row for row in manifest['clips']}
    reel = bpy.data.actions.new('Preview_LabradorReel'); frame = 1; timeline = []
    for name, cycles, label, view in SHOTS:
        spec = specs[name]; source = bpy.data.actions[name]
        count = round(spec['duration']*cycles*FPS)
        timeline.append({'clip': name, 'label': label, 'view': view, 'first_frame': frame, 'last_frame': frame+count-1})
        for i in range(count):
            source_frame = 1 + ((i/FPS*manifest['fps']) % (spec['frames'][1]-1))
            set_action(rig, source); scene.frame_set(int(source_frame), subframe=source_frame-int(source_frame))
            bpy.context.view_layer.update()
            matrices = {bone.name: bone.matrix_basis.copy() for bone in rig.pose.bones}
            set_action(rig, None); scene.frame_set(frame)
            for bone in rig.pose.bones: bone.matrix_basis = matrices[bone.name]
            set_action(rig, reel)
            for bone in rig.pose.bones:
                for channel in ('location', 'rotation_quaternion', 'scale'):
                    bone.keyframe_insert(channel, frame=frame, group=bone.name)
            frame += 1
    for curve in channels(reel):
        for key in curve.keyframe_points: key.interpolation = 'LINEAR'
    set_action(rig, reel)
    return timeline, frame-1


def render(base):
    production = base/'production/LabradorPet_Animations.blend'
    source_sha = hashlib.sha256(production.read_bytes()).hexdigest()
    bpy.ops.wm.open_mainfile(filepath=str(production))
    rig = bpy.data.objects['LabradorPet']; scene = bpy.context.scene
    manifest = json.loads((base/'export/animation-manifest.json').read_text())
    timeline, end = bake(rig, manifest)
    camera = stage(scene)
    scene.render.resolution_x = 960; scene.render.resolution_y = 640; scene.render.fps = FPS
    font = bpy.data.fonts.load('/System/Library/Fonts/AppleSDGothicNeo.ttc')
    material = bpy.data.materials.new('LabradorReelText'); material.use_nodes = True
    shader = material.node_tree.nodes['Principled BSDF']
    shader.inputs['Base Color'].default_value = (.07, .09, .13, 1)
    shader.inputs['Emission Color'].default_value = (.07, .09, .13, 1)
    shader.inputs['Emission Strength'].default_value = 1
    def caption(name, body, y, size):
        curve = bpy.data.curves.new(name, 'FONT'); curve.body = body; curve.font = font
        curve.size = size; curve.align_x = 'CENTER'; curve.align_y = 'CENTER'
        obj = bpy.data.objects.new(name, curve); scene.collection.objects.link(obj)
        obj.parent = camera; obj.location = (0, y, -1); obj.data.materials.append(material); obj.visible_shadow = False
        return obj
    caption('ReelTitle', '래브라도 / Labrador', .57, .040)
    label = caption('ReelCaption', '', -.58, .042)
    def update(scene, *unused):
        shot = next((row for row in timeline if row['first_frame'] <= scene.frame_current <= row['last_frame']), timeline[-1])
        label.data.body = shot['label']
        camera.location = (1.7, .1, .70) if shot['view'] == 'side' else (1.5, -1.65, .95)
        camera.rotation_euler = (Vector((0, .04, .44))-camera.location).to_track_quat('-Z', 'Y').to_euler()
    bpy.app.handlers.frame_change_pre.append(update)
    scene.frame_start = 1; scene.frame_end = end; scene.frame_set(1)
    raw = base/'export/LabradorPet_Motions_Render.mp4'
    scene.render.image_settings.media_type = 'VIDEO'; scene.render.image_settings.file_format = 'FFMPEG'
    scene.render.ffmpeg.format = 'MPEG4'; scene.render.ffmpeg.codec = 'H264'
    scene.render.ffmpeg.constant_rate_factor = 'HIGH'; scene.render.ffmpeg.ffmpeg_preset = 'GOOD'
    scene.render.ffmpeg.gopsize = FPS; scene.render.ffmpeg.audio_codec = 'NONE'; scene.render.filepath = str(raw)
    print('LABRADOR_REEL_BEGIN', end, flush=True)
    bpy.ops.render.render(animation=True)
    if not raw.exists():
        candidates = list(raw.parent.glob('LabradorPet_Motions_Render*.mp4'))
        if len(candidates) != 1: raise RuntimeError('Cannot identify reel output')
        candidates[0].replace(raw)
    output = base/'export/LabradorPet_Motions.mp4'
    streaming = faststart(raw, output); raw.unlink()
    unchanged = hashlib.sha256(production.read_bytes()).hexdigest() == source_sha
    if not unchanged: raise RuntimeError('Production source changed during render')
    report = {'file': str(output.relative_to(base)), 'width': 960, 'height': 640, 'fps': FPS,
              'frames': end, 'duration_seconds': end/FPS, 'bytes': output.stat().st_size,
              'sha256': hashlib.sha256(output.read_bytes()).hexdigest(), 'source_unchanged': unchanged,
              'timeline': timeline, 'streaming': streaming,
              'scope': 'Final two standing clips. Mouse ear/head/coat/eyelid reactions are in the interactive preview; no hands or sitting are shown.'}
    (base/'video-summary.json').write_text(json.dumps(report, ensure_ascii=False, indent=2)+'\n')
    print('LABRADOR_REEL_COMPLETE', str(output), end/FPS, flush=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(); parser.add_argument('--base', type=Path, required=True)
    args = parser.parse_args(sys.argv[sys.argv.index('--')+1:]); render(args.base.resolve())
