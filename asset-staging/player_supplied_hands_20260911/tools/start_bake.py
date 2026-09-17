import bpy,json,sys
from pathlib import Path
stage=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(stage/'tools'))
from bake_supplied import bake_supplied
bpy.ops.wm.open_mainfile(filepath=str(stage/'geometry/supplied_left_rigged.blend'))
scene=bpy.context.scene
high=bpy.data.collections['Source_High_Resolution'];high.hide_viewport=False;high.hide_render=False
def enable(c):
    c.exclude=False;c.hide_viewport=False
    for x in c.children:enable(x)
enable(bpy.context.view_layer.layer_collection)
pairs=[('Supplied_Skin',bpy.data.objects['Supplied_AnatomicalHand'],bpy.data.objects['HighRes_Supplied_AnatomicalHand'])]
pairs += [('Supplied_Nail',bpy.data.objects['Nail_'+d],bpy.data.objects['HighRes_Nail_'+d]) for d in ('thumb','index','middle','ring','little')]
out=stage/'mac_output/iteration_01';out.mkdir(parents=True,exist_ok=True)
report=bake_supplied(scene,pairs,out,4096,2)
high.hide_render=True;high.hide_viewport=True
(out/'bake_report.json').write_text(json.dumps(report,indent=2))
bpy.context.preferences.filepaths.save_version=0
bpy.ops.wm.save_as_mainfile(filepath=str(out/'supplied_left_baked.blend'),check_existing=False)
print('LEFT_BAKE_COMPLETE',flush=True)
