import bpy,json
from pathlib import Path
bpy.ops.wm.open_mainfile(filepath=str(Path('asset-staging/player_hands_proportions_20260911/mac_output/iteration_01/bilateral_hands_proportions.blend').resolve()))
r={}
for m in bpy.data.materials:
 if m.name.startswith('Detailed_'):
  r[m.name]={'nodes':[{ 'name':n.name,'type':n.bl_idname,'image':n.image.name if n.type=='TEX_IMAGE' and n.image else None,'inputs':{x.name:list(x.default_value)if hasattr(x.default_value,'__len__') else x.default_value for x in n.inputs if hasattr(x,'default_value') and x.type in ('VALUE','RGBA','VECTOR')}} for n in m.node_tree.nodes], 'links':[(l.from_node.name,l.from_socket.name,l.to_node.name,l.to_socket.name)for l in m.node_tree.links]}
for o in bpy.data.objects:
 if True:
  if o.type=='ARMATURE':r[o.name]={'matrix':list(map(list,o.matrix_world)),'bones':{b.name:{'head':list(b.head_local),'tail':list(b.tail_local),'matrix':list(map(list,b.matrix_local))}for b in o.data.bones}}
  if o.type=='MESH':r[o.name]={'vertices':len(o.data.vertices),'materials':[m.name for m in o.data.materials], 'attrs':[a.name for a in o.data.attributes], 'uvs':[u.name for u in o.data.uv_layers], 'matrix':list(map(list,o.matrix_world))}
Path('asset-staging/player_fingers_detail_20260911/tools/material_audit/source_probe.json').write_text(json.dumps(r,indent=2))
print('PROBE_COMPLETE')
