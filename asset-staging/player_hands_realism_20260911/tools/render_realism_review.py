"""Complete accepted PBR candidate views; leave blend/GLBs byte-identical."""
import argparse,json,sys
from pathlib import Path
import bpy
sys.path.insert(0,str(Path(__file__).resolve().parent))
from build_hands_realistic import digest,activate,descendants,render_views
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--input-dir',type=Path,required=True);p.add_argument('--output-dir',type=Path,required=True);a=p.parse_args(sys.argv[sys.argv.index('--')+1:]);source=a.input_dir.resolve();output=a.output_dir.resolve();assert bpy.app.background
models=[output/n for n in('bilateral_hands_realistic.blend','left_hand_realistic.glb','right_hand_realistic.glb')];hashes=[digest(p)for p in models]
bpy.ops.wm.open_mainfile(filepath=str(models[0]));scene=bpy.data.scenes['Bilateral_Realistic_Review'];activate(scene);hands={}
for side in('left','right'):
 holder=scene.objects[side.upper()+'_PreviewTranslationOnly'];objects=descendants(holder);rig=next(o for o in objects if o.type=='ARMATURE');skin=next(o for o in objects if o.type=='MESH'and'Anatomical'in o.name);hands[side]=(holder,objects,rig,skin)
report=json.loads((output/'build_report.json').read_text());render_views(scene,hands,source,output,report)
assert hashes==[digest(p)for p in models];report['outputs']={p.name:{'bytes':p.stat().st_size,'sha256':digest(p)}for p in output.iterdir()if p.is_file()and p.name!='build_report.json'};(output/'build_report.json').write_text(json.dumps(report,indent=2,ensure_ascii=False));print('REALISM_REVIEW_RENDERS_COMPLETE')
