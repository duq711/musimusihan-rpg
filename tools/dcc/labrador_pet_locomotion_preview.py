"""Small side/three-quarter evaluated-skin previews of captured locomotion."""
import argparse
import sys
from pathlib import Path

import bpy
from mathutils import Vector

sys.path.insert(0,str(Path(__file__).resolve().parent))
from labrador_pet import set_action
from labrador_pet_preview import stage


def render(base):
    bpy.ops.wm.open_mainfile(filepath=str(base/'production/LabradorPet_Locomotion.blend'))
    scene=bpy.context.scene;rig=bpy.data.objects['LabradorPet'];camera=stage(scene)
    scene.render.resolution_x=600;scene.render.resolution_y=420
    output=base/'validation/locomotion/render';output.mkdir(parents=True,exist_ok=True)
    for clip,frames in [('Walk',[1,13,24,36]),('Run',[1,7,13,19])]:
        set_action(rig,bpy.data.actions[clip])
        for f in frames:
            scene.frame_set(f);bpy.context.view_layer.update()
            scene.render.filepath=str(output/f'{clip}_{f:03}.png');bpy.ops.render.render(write_still=True)
    camera.location=(1.6,-1.3,.9)
    camera.rotation_euler=(Vector((0,.0,.42))-camera.location).to_track_quat('-Z','Y').to_euler()
    set_action(rig,bpy.data.actions['Run']);scene.frame_set(7)
    scene.render.filepath=str(output/'Run_ThreeQuarter.png');bpy.ops.render.render(write_still=True)


if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--base',type=Path,required=True)
    args=parser.parse_args(sys.argv[sys.argv.index('--')+1:]);render(args.base.resolve())
