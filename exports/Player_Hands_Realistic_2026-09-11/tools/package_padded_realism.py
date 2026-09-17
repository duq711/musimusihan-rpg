"""Replace only packed atlas images in the approved editable presentation file."""
import argparse
import ast
import hashlib
import json
from pathlib import Path
import sys

import bpy


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--input-dir',type=Path,required=True)
parser.add_argument('--output-dir',type=Path,required=True)
args=parser.parse_args(sys.argv[sys.argv.index('--')+1:])
source=args.input_dir.resolve();output=args.output_dir.resolve()
assert bpy.app.background
original=source/'bilateral_hands_realistic.blend'
destination=output/original.name
assert not destination.exists()
sources={p.name:digest(p) for p in [original,*source.glob('*.glb'),*source.glob('realistic_hands_*.png')]}
# Reuse the already checked snapshot definitions without executing its save workflow.
tree=ast.parse(Path(__file__).with_name('setup_realism_review.py').read_text())
definitions=ast.Module(body=[n for n in tree.body if isinstance(n,(ast.Import,ast.ImportFrom,ast.FunctionDef))],type_ignores=[])
namespace={};exec(compile(definitions,'approved_model_signature_functions','exec'),namespace)
snapshot=namespace['snapshot']
bpy.ops.wm.open_mainfile(filepath=str(original))
before=snapshot()
presentation={'scene':bpy.context.scene.name,'camera':bpy.context.scene.camera.name,
              'camera_matrix':[list(r) for r in bpy.context.scene.camera.matrix_world],
              'ortho_scale':bpy.context.scene.camera.data.ortho_scale,
              'samples':bpy.context.scene.cycles.samples,
              'denoising':bpy.context.scene.cycles.use_denoising,
              'resolution':[bpy.context.scene.render.resolution_x,bpy.context.scene.render.resolution_y]}
changed=[]
for mode in ('basecolor','normal','roughness'):
    name='realistic_hands_'+mode
    image=bpy.data.images[name]
    colorspace=image.colorspace_settings.name
    if image.packed_file:image.unpack(method='REMOVE')
    image.filepath_raw=str(output/(name+'.png'))
    image.reload()
    assert image.colorspace_settings.name==colorspace
    image.pack()
    assert hashlib.sha256(image.packed_file.data).hexdigest()==digest(output/(name+'.png'))
    image.filepath_raw='//'+name+'.png'
    changed.append(name)
after=snapshot()
for category in ('meshes','objects','materials'):
    assert before[category]==after[category],category+' changed'
assert set(before['images'])==set(after['images'])
for name,row in before['images'].items():
    if name not in changed:assert row==after['images'][name]
    else:
        assert {k:v for k,v in row.items() if k!='packed'}=={k:v for k,v in after['images'][name].items() if k!='packed'}
bpy.context.preferences.filepaths.save_version=0
bpy.ops.wm.save_as_mainfile(filepath=str(destination),check_existing=False,relative_remap=False)
bpy.ops.wm.open_mainfile(filepath=str(destination))
assert snapshot()==after
assert sources=={p.name:digest(p) for p in [original,*source.glob('*.glb'),*source.glob('realistic_hands_*.png')]}
assert bpy.context.scene.name==presentation['scene']
assert [list(r) for r in bpy.context.scene.camera.matrix_world]==presentation['camera_matrix']
assert bpy.context.scene.cycles.samples==24 and bpy.context.scene.cycles.use_denoising
report={'status':'passed','source_blend_sha256':sources[original.name],
        'output_blend_sha256':digest(destination),'presentation_preserved':presentation,
        'source_files_unchanged':sources,'geometry_rest_pose_morph_weights_uv_material_graph_exact':True,
        'changed_data':'Only three packed image payloads and their same-named relative output paths.',
        'before_signatures':before,'after_signatures':after}
(output/'padded_model_preservation_report.json').write_text(json.dumps(report,indent=2,ensure_ascii=False))
build=json.loads((source/'build_report.json').read_text())
build['iteration']='04 atlas background padding only'
build['renders']={}
build['reference_previous_geometry_views']={'directory':str(source),'files':[p.name for p in source.glob('*.png') if not p.name.startswith('realistic_hands_')],
                                            'note':'Earlier actual views remain geometry/detail references; new atlas padding affects distance filtering only.'}
build['atlas_padding_report']='atlas_padding_report.json'
build['model_preservation_report']='padded_model_preservation_report.json'
build['outputs']={p.name:{'bytes':p.stat().st_size,'sha256':digest(p)} for p in output.iterdir() if p.is_file()}
for side in ('left','right'):
    exported=output/(side+'_hand_realistic.glb')
    build['hands'][side]['export'].update({'sha256':digest(exported),'bytes':exported.stat().st_size})
padding=json.loads((output/'atlas_padding_report.json').read_text())
for mode,texture in build['textures'].items():
    texture.pop('sample_min',None);texture.pop('sample_max',None)
    texture['padding_rgb8_min']=padding['textures'][mode]['minimum_rgb']
    texture['padding_rgb8_max']=padding['textures'][mode]['maximum_rgb']
    texture['authored_pixels_exact']=True
build['inherited_export_tangent_repair']=build.pop('export_tangent_repair')
build['inherited_export_tangent_repair']['note']='This repair was completed in source iteration 03. Its TANGENT bytes remain identical in iteration 04.'
build['delivery_review_setup']={'report':'padded_model_preservation_report.json','status':'passed',
                                'original_setup_report':str(source/'review_setup_report.json'),
                                'presentation_unchanged':True}
(output/'build_report.json').write_text(json.dumps(build,indent=2,ensure_ascii=False))
print('PADDED_REALISM_BLEND_READY',digest(destination),flush=True)
