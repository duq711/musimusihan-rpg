import bpy,json
from pathlib import Path
stage=Path(__file__).resolve().parents[1]
bpy.ops.wm.open_mainfile(filepath=str(stage.parent/'player_hands_realism_20260911/mac_output/iteration_04/bilateral_hands_realistic.blend'))
s=bpy.data.scenes['Bilateral_Realistic_Review'] if 'Bilateral_Realistic_Review' in bpy.data.scenes else bpy.context.scene
out=[]
for skin in bpy.data.objects:
 if skin.type!='MESH' or 'Anatomical' not in skin.name or len(skin.data.vertices)!=14988:continue
 for a,b in [(11701,11702),(11705,11706),(11709,11710),(2879,2880)]:
  x=skin.data.vertices[a];y=skin.data.vertices[b]
  out.append({'object':skin.name,'pair':[a,b],'distance_m':(x.co-y.co).length,'rounded_keys_differ':tuple(round(c,6) for c in x.co)!=tuple(round(c,6) for c in y.co),'groups_a':[(g.group,g.weight) for g in x.groups],'groups_b':[(g.group,g.weight) for g in y.groups]})
print('SOURCE_SEAM',json.dumps(out))
(stage/'diagnostics/thumb_source_seam.json').write_text(json.dumps(out,indent=2))
