import bpy,json,sys
from pathlib import Path
root=Path.cwd();sys.path.insert(0,str(root/'asset-staging/player_fingers_detail_20260911/tools'))
from detail_materials import _procedural,_surface,_protected_non_skin_texels
bpy.ops.wm.open_mainfile(filepath=str(root/'asset-staging/player_hands_proportions_20260911/mac_output/iteration_01/bilateral_hands_proportions.blend'))
scene=bpy.data.scenes['Bilateral_Realistic_Review'];bpy.context.window.scene=scene
holder=scene.objects['LEFT_PreviewTranslationOnly']
def descendants(root):
 result=[]
 for child in root.children:result.append(child);result.extend(descendants(child))
 return result
objects=descendants(holder)
hand={'holder':holder,'objects':objects,'rig':next(o for o in objects if o.type=='ARMATURE'),'skin':next(o for o in objects if o.type=='MESH'and 'Anatomical' in o.name)}
materials={name:_procedural(bpy.data.materials[name],1.0) for name in ('Detailed_Skin','Detailed_Nail')}
surface,report=_surface(scene,hand,materials)
report['non_skin_interior_samples']=len(_protected_non_skin_texels(hand,4096))
report.update({'node_counts':{name:len(r['material'].node_tree.nodes)for name,r in materials.items()},'pose_neutral':all(p.matrix_basis.is_identity for p in hand['rig'].pose.bones)})
for name,record in materials.items():
 for node in record['material'].node_tree.nodes:
  assert node.bl_idname!='ShaderNodeGroup'
Path('asset-staging/player_fingers_detail_20260911/tools/material_audit/graph_probe.json').write_text(json.dumps(report,indent=2))
print('GRAPH_PROBE_PASS',report)
