"""Render disposable motion contact sheets without saving the production blend."""
import argparse
import sys
from pathlib import Path
import bpy
from mathutils import Vector


def render(base):
    bpy.ops.wm.open_mainfile(filepath=str(base/'production/ShepherdPet_Animations.blend'))
    rig=next(o for o in bpy.context.scene.objects if o.type=='ARMATURE')
    scene=bpy.context.scene
    scene.render.engine='CYCLES';scene.cycles.device='CPU';scene.cycles.samples=12
    scene.render.resolution_x=512;scene.render.resolution_y=400;scene.render.resolution_percentage=100
    scene.render.image_settings.file_format='PNG'
    scene.world=bpy.data.worlds.new('ReviewWorld');scene.world.color=(.20,.20,.20)
    scene.view_settings.view_transform='AgX'
    bpy.ops.mesh.primitive_plane_add(size=200,location=(0,0,-.005))
    floor=bpy.context.object;floor.name='ReviewFloor'
    material=bpy.data.materials.new('ReviewStage');material.diffuse_color=(.12,.17,.23,1)
    floor.data.materials.append(material)
    for loc,energy,size in [((1,-1,2),180,2),((-1,-.5,1),80,2),((0,2,1.8),130,1.5)]:
        bpy.ops.object.light_add(type='AREA',location=loc)
        light=bpy.context.object;light.data.energy=energy;light.data.shape='DISK';light.data.size=size
    bpy.ops.object.camera_add(location=(1.7,.10,.63))
    camera=bpy.context.object;scene.camera=camera;camera.data.type='ORTHO';camera.data.ortho_scale=1.45
    camera.rotation_euler=(Vector((0,.10,.34))-camera.location).to_track_quat('-Z','Y').to_euler()
    groups={
        'combat_search':[('CombatBite',[1,13,19,28,37]),('SearchSniff',[1,23,46]),('SearchFound',[1,23,46])],
        'retrieval':[('RetrievePickup',[1,16,25,35,46]),('RetrieveCarryWalk',[1,10,19]),('RetrieveDrop',[1,16,25,35,46])],
        'feeding':[('EatStart',[1,16,31]),('EatLoop',[1,11,21,31]),('EatEnd',[1,16,31])],
        'petting':[('PetSit',[1,16,31,46]),('PetEnjoy',[1,23,46,69]),('PetRise',[1,13,25,37])],
        'locomotion':[('Walk',[1,7,13,19]),('Run',[1,3,5,7,9,11,13])],
    }
    output=base/'validation/visual';output.mkdir(parents=True,exist_ok=True)
    for group,clips in groups.items():
        for name,frames in clips:
            action=bpy.data.actions[name];rig.animation_data.action=action;rig.animation_data.action_slot=action.slots[0]
            for frame in frames:
                scene.frame_set(frame)
                scene.render.filepath=str(output/f'{group}_{name}_{frame:03}.png')
                bpy.ops.render.render(write_still=True)
    print('PREVIEW_COMPLETE',flush=True)


if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--base',type=Path,required=True)
    args=parser.parse_args(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else [])
    render(args.base.resolve())
