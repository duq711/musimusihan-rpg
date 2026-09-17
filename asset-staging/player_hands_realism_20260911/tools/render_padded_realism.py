"""Three final actual Blender views after atlas padding; preserve saved asset bytes."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import sys

import bpy
from mathutils import Vector


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def descendants(obj):
    result=[]
    for child in obj.children:
        result.append(child)
        result.extend(descendants(child))
    return result


parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--input-dir',type=Path,required=True)
parser.add_argument('--output-dir',type=Path,required=True)
args=parser.parse_args(sys.argv[sys.argv.index('--')+1:])
source=args.input_dir.resolve();output=args.output_dir.resolve()
assert bpy.app.background
models=[output/'bilateral_hands_realistic.blend',*output.glob('*.glb')]
hashes={p.name:digest(p) for p in models}
bpy.ops.wm.open_mainfile(filepath=str(models[0]))
scene=bpy.data.scenes['Bilateral_Realistic_Review'];bpy.context.window.scene=scene
holder=scene.objects['LEFT_PreviewTranslationOnly']
right=descendants(scene.objects['RIGHT_PreviewTranslationOnly'])
visibility={o.name:o.hide_render for o in scene.objects}
camera=scene.camera
report=json.loads((output/'build_report.json').read_text())
configurations=[('preview_finger_dorsum',(0,.135,.005),(0,-.08,1),.205,(1400,1200),40,False),
                ('finger_palm_closeup',(0,.135,0),(0,.03,-1),.205,(1400,1200),24,False),
                ('bilateral_dorsum',(0,-.035,0),(0,0,1),.68,(1600,1300),24,True)]
for name,center_native,direction,scale,resolution,samples,bilateral in configurations:
    for obj in scene.objects:obj.hide_render=visibility[obj.name]
    if not bilateral:
        for obj in right:obj.hide_render=True
    center=Vector(center_native) if bilateral else holder.matrix_world@Vector(center_native)
    camera.location=center+Vector(direction).normalized()*1.2
    camera.rotation_euler=(center-camera.location).to_track_quat('-Z','Y').to_euler()
    camera.data.ortho_scale=scale
    scene.cycles.samples=samples;scene.cycles.use_denoising=True
    scene.render.resolution_x,scene.render.resolution_y=resolution
    scene.render.resolution_percentage=100
    image=output/(name+'.png');assert not image.exists()
    scene.render.filepath=str(image);bpy.ops.render.render(write_still=True)
    report['renders'][name]={'file':image.name,'samples':samples,'denoising':True,
                            'resolution':list(resolution),'camera_world':[list(r) for r in camera.matrix_world],
                            'orthographic_scale':scale,'pose':'neutral','actual_blender_render':True}
    report['outputs'][image.name]={'bytes':image.stat().st_size,'sha256':digest(image)}
    (output/'build_report.json').write_text(json.dumps(report,indent=2,ensure_ascii=False))
    print('PADDED_REALISM_RENDER',name,flush=True)
before=output/'realism_before_after_before.png';after=output/'realism_before_after_after.png'
assert not before.exists() and not after.exists()
shutil.copy2(source/before.name,before)
shutil.copy2(output/'preview_finger_dorsum.png',after)
report['comparison']['method']='Before reuses the preserved direct grey Blender render; after is the new direct padded-atlas closeup. Identical camera/light/neutral pose and 40 samples; no compositing.'
report['comparison']['before_source']=str(source/before.name)
report['comparison']['settings']['after_reuses_identical_original_preview_pixels']=False
report['comparison']['settings']['after_equals_new_iteration04_preview_pixels']=True
for p in (before,after):report['outputs'][p.name]={'bytes':p.stat().st_size,'sha256':digest(p)}
assert hashes=={p.name:digest(p) for p in models}
(output/'build_report.json').write_text(json.dumps(report,indent=2,ensure_ascii=False))
print('PADDED_REALISM_REVIEW_COMPLETE',flush=True)
