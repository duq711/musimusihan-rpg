"""Render both final authored hands with neutral lighting, without saving model edits."""
import argparse,json,hashlib,sys
from pathlib import Path
import bpy
from mathutils import Vector
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--output-dir',type=Path,required=True);a=p.parse_args(sys.argv[sys.argv.index('--')+1:]);output=a.output_dir.resolve();assert bpy.app.background
blend=output/'bilateral_hands_realistic.blend';beforehash=hashlib.sha256(blend.read_bytes()).hexdigest();bpy.ops.wm.open_mainfile(filepath=str(blend));scene=bpy.data.scenes['Bilateral_Realistic_Review'];bpy.context.window.scene=scene
for obj in scene.objects:
 if obj.type=='MESH'and'UpperArm'in obj.name:obj.hide_render=True
scene.cycles.samples=24;scene.cycles.use_denoising=True;scene.render.resolution_x=1600;scene.render.resolution_y=1300;scene.render.resolution_percentage=100;scene.camera.data.ortho_scale=.68
report=json.loads((output/'build_report.json').read_text())
for name,direction in [('bilateral_dorsum',(0,0,1)),('bilateral_palm',(0,0,-1))]:
 center=Vector((0,-.035,0));scene.camera.location=center+Vector(direction)*1.2;scene.camera.rotation_euler=(center-scene.camera.location).to_track_quat('-Z','Y').to_euler();destination=output/(name+'.png');assert not destination.exists();scene.render.filepath=str(destination);bpy.ops.render.render(write_still=True)
 report['renders'][name]={'file':destination.name,'pose':'neutral bilateral','resolution':[1600,1300],'samples':24,'denoising':True,'ortho_scale':.68,'lighting':'same original review lights; no SSS/compositing'}
 report['outputs'][destination.name]={'bytes':destination.stat().st_size,'sha256':hashlib.sha256(destination.read_bytes()).hexdigest()}
assert beforehash==hashlib.sha256(blend.read_bytes()).hexdigest();(output/'build_report.json').write_text(json.dumps(report,indent=2,ensure_ascii=False));print('BILATERAL_REALISM_RENDERS_COMPLETE')
