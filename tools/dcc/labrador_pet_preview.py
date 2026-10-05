"""Bright studio QA and final poster for the production Labrador care clips."""
import argparse
import json
import sys
from pathlib import Path

import bpy
from mathutils import Vector

sys.path.insert(0,str(Path(__file__).resolve().parent))
from labrador_pet import set_action


def stage(scene):
    scene.render.engine='BLENDER_EEVEE';scene.eevee.taa_render_samples=8
    scene.render.resolution_x=760;scene.render.resolution_y=560;scene.render.resolution_percentage=100
    scene.render.image_settings.file_format='PNG';scene.view_settings.view_transform='AgX'
    scene.world=bpy.data.worlds.new('LabradorStudioWorld');scene.world.use_nodes=True
    node=scene.world.node_tree.nodes['Background'];node.inputs['Color'].default_value=(.68,.71,.76,1);node.inputs['Strength'].default_value=.65
    bpy.ops.mesh.primitive_plane_add(size=20,location=(0,0,-.001))
    floor=bpy.context.object;floor.name='PreviewFloor';mat=bpy.data.materials.new('StudioFloor');mat.use_nodes=True
    shader=mat.node_tree.nodes.get('Principled BSDF');shader.inputs['Base Color'].default_value=(.30,.33,.38,1);shader.inputs['Roughness'].default_value=.9
    floor.data.materials.append(mat)
    for position,energy,size in [((1.2,-1.7,2.0),300,2.3),((-1.5,-.7,1.3),220,2.0),((.3,1.8,1.6),220,1.8)]:
        bpy.ops.object.light_add(type='AREA',location=position)
        light=bpy.context.object;light.data.energy=energy;light.data.size=size
        light.rotation_euler=(Vector((0,0,.4))-light.location).to_track_quat('-Z','Y').to_euler()
    bpy.ops.object.camera_add(location=(1.7,.1,.65));camera=bpy.context.object;scene.camera=camera
    camera.data.type='ORTHO';camera.data.ortho_scale=2.0
    camera.rotation_euler=(Vector((0,.04,.44))-camera.location).to_track_quat('-Z','Y').to_euler()
    return camera


def render(base,blend):
    bpy.ops.wm.open_mainfile(filepath=str(blend))
    rig=bpy.data.objects['LabradorPet'];scene=bpy.context.scene;camera=stage(scene)
    output=base/'validation/motion';output.mkdir(parents=True,exist_ok=True)
    groups={'IdleFriendly':[1,90,180,314],'PetEnjoy':[1,31,61,91,121]}
    poses=[]
    for name,frames in groups.items():
        set_action(rig,bpy.data.actions[name])
        for frame in frames:
            scene.frame_set(frame);bpy.context.view_layer.update()
            positions={b.name:list((rig.matrix_world @ b.matrix).translation) for b in rig.pose.bones
                       if b.name.startswith(('Body_','Back_','Torso','FrontUpper','FrontLower','BackLeg','BackUpper','BackLower','IKFront','IKBack','FF','Head_'))}
            poses.append({'clip':name,'frame':frame,'joints_world':positions})
            scene.render.filepath=str(output/f'{name}_{frame:03}.png');bpy.ops.render.render(write_still=True)
    (base/'preview-pose-samples.json').write_text(json.dumps({'poses':poses},indent=2)+'\n')
    if blend.parent.name=='production':
        set_action(rig,bpy.data.actions['IdleFriendly']);scene.frame_set(1)
        camera.location=(1.5,-1.65,.95);camera.rotation_euler=(Vector((0,.0,.42))-camera.location).to_track_quat('-Z','Y').to_euler()
        scene.render.resolution_x=1100;scene.render.resolution_y=780
        scene.render.filepath=str(base/'export/LabradorPet_Poster.png');bpy.ops.render.render(write_still=True)
    print('LABRADOR_PREVIEW_COMPLETE',flush=True)


if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--base',type=Path,required=True);parser.add_argument('--blend',type=Path)
    args=parser.parse_args(sys.argv[sys.argv.index('--')+1:]);base=args.base.resolve()
    render(base,args.blend.resolve() if args.blend else base/'production/LabradorPet_Animations.blend')
