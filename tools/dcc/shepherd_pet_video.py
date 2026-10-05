"""Render a requested MP4 showreel on this Mac without changing source assets.

Blender 5.2: ImageFormatSettings.media_type must be VIDEO before FFMPEG.
Run: Blender --background --disable-autoexec --python this.py -- --base DIR
"""
import argparse
import hashlib
import json
import math
import sys
from pathlib import Path

import bpy
from mathutils import Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
from mp4_faststart import faststart

SOURCE_FPS=30
VIDEO_FPS=24
SHOTS=[
    ('IdleFriendly',1,'편안한 대기 / Friendly idle','threequarter'),
    ('Walk',4,'걷기 / Walk','side'),
    ('Run',4,'달리기 / Run','side'),
    ('CombatBite',1,'물기 공격 / Bite','threequarter'),
    ('SearchSniff',1,'냄새 맡기 / Sniff','threequarter'),
    ('SearchWalk',1,'냄새 탐색 / Scent walk','side'),
    ('SearchFound',1,'찾았다! / Found','threequarter'),
    ('RetrievePickup',1,'줍기 / Pick up','threequarter'),
    ('RetrieveCarryWalk',2,'물고 걷기 / Carry','side'),
    ('RetrieveDrop',1,'내려놓기 / Drop','threequarter'),
    ('EatStart',1,'밥 먹기 / Feeding','threequarter'),
    ('EatLoop',2,'밥 먹기 / Feeding','threequarter'),
    ('EatEnd',1,'밥 먹기 / Feeding','threequarter'),
    ('PetSit',1,'앉아서 쓰담 반응 / Petting reaction','threequarter'),
    ('PetEnjoy',1,'앉아서 쓰담 반응 / Petting reaction','threequarter'),
    ('PetRise',1,'일어나기 / Rise','threequarter'),
]


def assign(rig,action):
    rig.animation_data.action=action
    if action and action.slots:rig.animation_data.action_slot=action.slots[0]


def bake_reel(rig,manifest):
    scene=bpy.context.scene
    specs={row['name']:row for row in manifest['clips']}
    reel=bpy.data.actions.new('Preview_Showreel');timeline=[];output_frame=1
    for name,cycles,label,view in SHOTS:
        spec=specs[name];source=bpy.data.actions[name]
        start,end=spec['frames'];interval=end-start
        count=round(spec['duration']*cycles*VIDEO_FPS)
        timeline.append({'clip':name,'label':label,'view':view,'first_frame':output_frame,'last_frame':output_frame+count-1,'cycles':cycles})
        for i in range(count):
            source_frame=start+(i/VIDEO_FPS*SOURCE_FPS%interval if spec['loop'] else min(interval,i/VIDEO_FPS*SOURCE_FPS))
            assign(rig,source);scene.frame_set(int(source_frame),subframe=source_frame-int(source_frame))
            bpy.context.view_layer.update()
            pose={b.name:b.matrix_basis.copy() for b in rig.pose.bones}
            assign(rig,None);scene.frame_set(output_frame)
            for bone in rig.pose.bones:bone.matrix_basis=pose[bone.name]
            assign(rig,reel)
            for bone in rig.pose.bones:
                for channel in ('location','rotation_quaternion','scale'):
                    bone.keyframe_insert(channel,frame=output_frame,group=bone.name)
            output_frame+=1
        print('REEL_BAKED',name,output_frame-1,flush=True)
    for layer in reel.layers:
        for strip in layer.strips:
            for bag in strip.channelbags:
                for curve in bag.fcurves:
                    for key in curve.keyframe_points:key.interpolation='LINEAR'
    assign(rig,reel)
    return timeline,output_frame-1


def material(name,color,emission=False):
    mat=bpy.data.materials.new(name);mat.use_nodes=True
    shader=mat.node_tree.nodes.get('Principled BSDF')
    shader.inputs['Base Color'].default_value=(*color,1)
    shader.inputs['Roughness'].default_value=.8
    if emission:
        shader.inputs['Emission Color'].default_value=(*color,1)
        shader.inputs['Emission Strength'].default_value=1
    return mat


def stage():
    scene=bpy.context.scene
    # Real-time Eevee shading keeps a showreel responsive on this Mac.
    scene.render.engine='BLENDER_EEVEE'
    scene.eevee.taa_render_samples=8
    scene.render.resolution_x=960;scene.render.resolution_y=640;scene.render.resolution_percentage=100
    scene.render.fps=VIDEO_FPS
    scene.world=bpy.data.worlds.new('ShowreelWorld');scene.world.use_nodes=True
    scene.world.node_tree.nodes['Background'].inputs['Color'].default_value=(.13,.16,.21,1)
    scene.world.node_tree.nodes['Background'].inputs['Strength'].default_value=.45
    scene.view_settings.view_transform='AgX'
    bpy.ops.mesh.primitive_plane_add(size=200,location=(0,0,-.005))
    bpy.context.object.name='ShowreelFloor'
    bpy.context.object.data.materials.append(material('ShowreelFloorMaterial',(.045,.065,.09)))
    for loc,energy,size in [((1,-1,2),100,2),((-1,-.5,1),35,2),((0,2,1.8),85,1.5)]:
        bpy.ops.object.light_add(type='AREA',location=loc)
        light=bpy.context.object;light.data.energy=energy;light.data.shape='DISK';light.data.size=size
    bpy.ops.object.camera_add(location=(1.5,-1.65,.83));camera=bpy.context.object
    scene.camera=camera;camera.data.type='ORTHO';camera.data.ortho_scale=1.65
    font=bpy.data.fonts.load('/System/Library/Fonts/AppleSDGothicNeo.ttc')
    text_material=material('ShowreelCaption',(.92,.95,1),True)
    def text(name,body,size,y):
        curve=bpy.data.curves.new(name,'FONT');curve.body=body;curve.font=font;curve.size=size;curve.align_x='CENTER';curve.align_y='CENTER'
        obj=bpy.data.objects.new(name,curve);scene.collection.objects.link(obj);obj.parent=camera;obj.location=(0,y,-1)
        obj.data.materials.append(text_material);obj.visible_shadow=False
        return obj
    text('ShowreelTitle','독일 셰퍼드 펫 모션 / German Shepherd',.037,.48)
    caption=text('ShowreelCaption','',.045,-.47)
    return camera,caption


def render(base):
    source=base/'production/ShepherdPet_Animations.blend'
    source_hash=hashlib.sha256(source.read_bytes()).hexdigest()
    bpy.ops.wm.open_mainfile(filepath=str(source))
    rig=next(o for o in bpy.context.scene.objects if o.type=='ARMATURE')
    manifest=json.loads((base/'motion-manifest.json').read_text())
    timeline,end=bake_reel(rig,manifest)
    camera,caption=stage();scene=bpy.context.scene
    def update(scene,*unused):
        shot=next((row for row in timeline if row['first_frame']<=scene.frame_current<=row['last_frame']),timeline[-1])
        caption.data.body=shot['label']
        camera.location=(1.8,.10,.67) if shot['view']=='side' else (1.5,-1.65,.83)
        camera.rotation_euler=(Vector((0,.10,.34))-camera.location).to_track_quat('-Z','Y').to_euler()
    bpy.app.handlers.frame_change_pre.append(update)
    scene.frame_start=1;scene.frame_end=end;scene.frame_set(1)
    output=base/'export/ShepherdPet_Motions.mp4';output.parent.mkdir(parents=True,exist_ok=True)
    scene.render.image_settings.media_type='VIDEO'
    scene.render.image_settings.file_format='FFMPEG'
    scene.render.ffmpeg.format='MPEG4';scene.render.ffmpeg.codec='H264'
    scene.render.ffmpeg.constant_rate_factor='HIGH';scene.render.ffmpeg.ffmpeg_preset='GOOD'
    scene.render.ffmpeg.audio_codec='NONE'
    scene.render.filepath=str(output)
    print('RENDER_BEGIN',end,'frames',end/VIDEO_FPS,'seconds',flush=True)
    bpy.ops.render.render(animation=True)
    if not output.exists():
        candidates=list(output.parent.glob('ShepherdPet_Motions*.mp4'))
        if len(candidates)!=1:raise RuntimeError('Cannot identify rendered video: '+str(candidates))
        candidates[0].replace(output)
    optimized=base/'export/ShepherdPet_Motions_Seekable.mp4'
    streaming=faststart(output,optimized)
    output.unlink()
    output=optimized
    assert hashlib.sha256(source.read_bytes()).hexdigest()==source_hash
    receipt={'file':output.name,'width':960,'height':640,'fps':VIDEO_FPS,'frames':end,'duration_seconds':end/VIDEO_FPS,'bytes':output.stat().st_size,'sha256':hashlib.sha256(output.read_bytes()).hexdigest(),'source_blend_sha256':source_hash,'source_unchanged':True,'timeline':timeline,'streaming':streaming,'scope':'Rendered animation showreel; gameplay and interaction props are not simulated.'}
    (base/'video-summary.json').write_text(json.dumps(receipt,ensure_ascii=False,indent=2)+'\n')
    print('VIDEO_COMPLETE',json.dumps({key:value for key,value in receipt.items() if key!='timeline'},ensure_ascii=False),flush=True)


if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--base',type=Path,required=True)
    args=parser.parse_args(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else [])
    render(args.base.resolve())
