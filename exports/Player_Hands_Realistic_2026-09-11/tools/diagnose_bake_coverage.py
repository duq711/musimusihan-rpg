"""Bake an independent white coverage matte using the original atlas and bake settings."""
import argparse
from array import array
import hashlib
import json
from pathlib import Path
import sys

import bpy
import numpy as np


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--input-dir',type=Path,required=True)
parser.add_argument('--output-dir',type=Path,required=True)
args=parser.parse_args(sys.argv[sys.argv.index('--')+1:])
source=args.input_dir.resolve();output=args.output_dir.resolve()
assert bpy.app.background
assert not output.exists() or not any(output.iterdir())
output.mkdir(parents=True,exist_ok=True)
blend=source/'bilateral_hands_realistic.blend';before=sha(blend)
bpy.ops.wm.open_mainfile(filepath=str(blend))
scene=bpy.data.scenes['Bilateral_Realistic_Review'];bpy.context.window.scene=scene
objects=[o for o in scene.objects if o.type=='MESH']
assert len(objects)==18,len(objects)
bpy.ops.object.select_all(action='DESELECT')
copies=[]
for obj in objects:
    copy=obj.copy();copy.data=obj.data.copy();scene.collection.objects.link(copy)
    copy.name='CoverageCopy_'+obj.name;matrix=obj.matrix_world.copy()
    copy.parent=None;copy.matrix_world=matrix
    copy.hide_render=False;copy.hide_viewport=False;copy.hide_set(False)
    for modifier in list(copy.modifiers):copy.modifiers.remove(modifier)
    if copy.data.shape_keys:copy.shape_key_clear()
    copy.select_set(True);copies.append(copy)
bpy.context.view_layer.objects.active=copies[0]
bpy.ops.object.join();surface=bpy.context.object
surface.name='Independent_White_Coverage_Surface'
surface.data.materials.clear()
white=bpy.data.materials.new('Diagnostic_Constant_White');white.use_nodes=True
nodes=white.node_tree.nodes;nodes.clear();links=white.node_tree.links
out=nodes.new('ShaderNodeOutputMaterial');emission=nodes.new('ShaderNodeEmission')
emission.inputs['Color'].default_value=(1,1,1,1);emission.inputs['Strength'].default_value=1
links.new(emission.outputs[0],out.inputs['Surface'])
surface.data.materials.append(white)
for polygon in surface.data.polygons:polygon.material_index=0
image=bpy.data.images.new('Independent_Bake_Coverage',width=4096,height=4096,alpha=False,float_buffer=True)
image.colorspace_settings.name='Non-Color';image.generated_color=(0,0,0,1)
target=nodes.new('ShaderNodeTexImage');target.image=image;nodes.active=target
for node in nodes:node.select=node==target
scene.render.engine='CYCLES';scene.cycles.device='CPU';scene.cycles.samples=4
scene.render.bake.margin=2;scene.render.bake.use_clear=True
scene.render.bake.use_selected_to_active=False
bpy.ops.object.bake(type='EMIT',use_clear=True,margin=2)
pixels=np.empty(4096*4096*4,dtype=np.float32);image.pixels.foreach_get(pixels)
coverage=pixels.reshape(4096,4096,4)[:,:,0].copy()
assert np.isfinite(coverage).all()
# Keep Blender's bottom-to-top row order explicit; PNG readers use flipped rows.
np.save(output/'coverage_blender_bottom_up.npy',coverage)
rough=bpy.data.images['realistic_hands_roughness']
roughpixels=np.empty(4096*4096*4,dtype=np.float32);rough.pixels.foreach_get(roughpixels)
roughness=roughpixels.reshape(4096,4096,4)[:,:,0]
valid=roughness>0
interior=coverage>=1-1e-6
partial=(coverage>1e-6)&(~interior)
low=valid&(roughness<70/255)
report={'status':'coverage_diagnostic_complete','source_blend_sha256':before,
        'source_blend_unchanged':sha(blend)==before,
        'settings':{'engine':'CYCLES','samples':4,'resolution':[4096,4096],'margin':2,
                    'use_clear':True,'shader':'constant white emission 1','normal_not_used':True,
                    'float_buffer':True,'array_row_order':'Blender bottom-to-top'},
        'copied_mesh_count':len(objects),'combined_vertices':len(surface.data.vertices),
        'coverage':{'minimum':float(coverage.min()),'maximum':float(coverage.max()),
                    'zero_pixels':int((coverage<=1e-6).sum()),'partial_pixels':int(partial.sum()),
                    'full_pixels':int(interior.sum())},
        'roughness_low_fringe':{'below_70_count':int(low.sum()),
                               'in_partial_coverage':int((low&partial).sum()),
                               'in_full_coverage':int((low&interior).sum()),
                               'in_zero_coverage':int((low&(coverage<=1e-6)).sum())}}
assert report['source_blend_unchanged']
(output/'coverage_report.json').write_text(json.dumps(report,indent=2))
print('WHITE_COVERAGE_DIAGNOSTIC_COMPLETE',json.dumps(report['coverage']),json.dumps(report['roughness_low_fringe']),flush=True)
