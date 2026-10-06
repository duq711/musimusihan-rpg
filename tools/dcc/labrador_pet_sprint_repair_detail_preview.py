import sys,math
from pathlib import Path
import bpy
from mathutils import Vector
sys.path.insert(0,'/Users/byeolee/Projects/musimusihan-rpg/tools/dcc')
from labrador_pet import set_action,update
from labrador_pet_preview import stage
base=Path('/Users/byeolee/Projects/musimusihan-rpg/asset-staging/labrador-sprint-repair-20261006')
bpy.ops.wm.open_mainfile(filepath=str(base/'production/LabradorPet_SprintRepair.blend'));scene=bpy.context.scene;rig=bpy.data.objects['LabradorPet'];camera=stage(scene)
camera.location=(1.55,-1.55,.68);camera.rotation_euler=(Vector((0,-.23,.36))-camera.location).to_track_quat('-Z','Y').to_euler();camera.data.ortho_scale=1.25
scene.render.resolution_x=720;scene.render.resolution_y=600;scene.eevee.taa_render_samples=32
out=base/'review/detail';out.mkdir(parents=True,exist_ok=True)
for ph in (.464285714,.75,.785714286,.9):
 set_action(rig,bpy.data.actions['Run']);f=1+ph*42;scene.frame_set(int(f),subframe=f-int(f));update();scene.render.filepath=str(out/f'Run_front_{round(ph*1000):03}.png');bpy.ops.render.render(write_still=True)
set_action(rig,bpy.data.actions['IdleFriendly']);scene.frame_set(1);update();scene.render.filepath=str(out/'Neutral_front.png');bpy.ops.render.render(write_still=True)
