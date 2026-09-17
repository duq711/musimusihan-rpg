"""Build a separate reference-refined candidate from the approved thumb roll."""
import argparse,hashlib,json,sys,shutil
from pathlib import Path
import bpy
from mathutils import Vector
sys.path.insert(0,str(Path(__file__).resolve().parent))
from build_finger_detail import collect,frozen
from reference_export import export_native
from refine_geometry import refine
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
p=argparse.ArgumentParser();p.add_argument('--source',type=Path,required=True);p.add_argument('--output-dir',type=Path,required=True);p.add_argument('--skip-bake',action='store_true');p.add_argument('--cap-strength',type=float,default=1.);a=p.parse_args(sys.argv[sys.argv.index('--')+1:]);src=a.source.resolve();out=a.output_dir.resolve();assert not out.exists();out.mkdir();original=sha(src)
bpy.ops.wm.open_mainfile(filepath=str(src));scene=bpy.data.scenes['Bilateral_Realistic_Review'];bpy.context.window.scene=scene;hands=collect(scene);before={s:frozen(h) for s,h in hands.items()}
report={'source':str(src),'source_sha256':original,'reference':'User supplied 5 fingers x 4 views, retained as visual guide; each actual comparison is a separate one-finger PNG.','hands':{s:refine(h,a.cap_strength) for s,h in hands.items()}}
assert all(frozen(h)==before[s] for s,h in hands.items()),'Protected rig, non-skin part, topology, UV or weights changed'
if a.skip_bake:
    for name in ('basecolor','normal','roughness'):shutil.copy2(src.parent/f'realistic_hands_{name}.png',out/f'realistic_hands_{name}.png')
    report['bake']='skipped geometry review only'
else:
    from detail_materials import bake_finger_detail
    report['bake']=bake_finger_detail(scene,hands,out,resolution=4096,samples=8,strength=1.)
for s,h in hands.items():report['hands'][s]['export']=export_native(scene,h['objects'],h['holder'],out/f'{s}_hand_finger_detail.glb')
visibility={o.name:o.hide_render for o in scene.objects};camera=scene.camera
for o in hands['right']['objects']:o.hide_render=True
center=hands['left']['holder'].matrix_world@Vector((0,.075,0));camera.location=center+Vector((0,0,1.2));camera.rotation_euler=(center-camera.location).to_track_quat('-Z','Y').to_euler();camera.data.ortho_scale=.295;scene.render.resolution_x=1400;scene.render.resolution_y=1200;scene.render.resolution_percentage=100;scene.cycles.samples=32;scene.render.filepath=str(out/'hand_dorsum.png');bpy.ops.render.render(write_still=True)
for o in scene.objects:o.hide_render=visibility[o.name]
bpy.context.preferences.filepaths.save_version=0;blend=out/'bilateral_hands_finger_detail.blend';bpy.ops.wm.save_as_mainfile(filepath=str(blend),check_existing=False,relative_remap=False)
report['blend_sha256']=sha(blend);report['script_sha256']={p.name:sha(p) for p in Path(__file__).parent.glob('*.py')};assert sha(src)==original
(out/'build_report.json').write_text(json.dumps(report,indent=2));print('PHOTOREF_BUILD_COMPLETE',out,flush=True)
