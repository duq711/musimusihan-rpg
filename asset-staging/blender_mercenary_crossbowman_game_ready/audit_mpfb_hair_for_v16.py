from pathlib import Path
import bpy

P=Path('/Users/duq711gmail.com/Documents/ChatGPT/무시무시한 rpg/asset-staging/blender_mercenary_crossbowman_game_ready/mpfb_base_test.blend')
bpy.ops.wm.open_mainfile(filepath=str(P))
for name in ('Mercenary_Male_Body','Mercenary_Male_Hair'):
 o=bpy.data.objects[name]
 print('OBJ',name,'TYPE',o.type,'PARENT',o.parent.name if o.parent else None)
 print('TRANSFORM',tuple(o.location),tuple(o.rotation_euler),tuple(o.scale))
 print('MODS',[(m.name,m.type,getattr(m,'show_render',None)) for m in o.modifiers])
 if o.type=='MESH':
  tris=sum(max(1,len(p.vertices)-2) for p in o.data.polygons)
  print('MESH',len(o.data.vertices),len(o.data.polygons),tris)
  print('MATS',[m.name if m else None for m in o.data.materials])
  for m in o.data.materials:
   if m and m.use_nodes and m.node_tree:
    print('MATSET',m.name,'blend',getattr(m,'surface_render_method',None),'cull',m.use_backface_culling)
    for node in m.node_tree.nodes:
     if node.type=='TEX_IMAGE' and node.image:
      print(' IMAGE',node.name,node.image.name,list(node.image.size),node.image.filepath)
 print('BBOX',[tuple(round(x,5) for x in c) for c in o.bound_box])

body=bpy.data.objects['Mercenary_Male_Body']
deps=bpy.context.evaluated_depsgraph_get(); ev=body.evaluated_get(deps)
mesh=bpy.data.meshes.new_from_object(ev,preserve_all_data_layers=True,depsgraph=deps)
pts=[ev.matrix_world@v.co for v in mesh.vertices]
full=(min(p.x for p in pts),max(p.x for p in pts),min(p.y for p in pts),max(p.y for p in pts),min(p.z for p in pts),max(p.z for p in pts))
s=1.78/(full[5]-full[4]);cx=(full[0]+full[1])*.5;cy=(full[2]+full[3])*.5
ids=set()
for p in mesh.polygons:
 c=ev.matrix_world@p.center
 nc=((c.x-cx)*s,(c.y-cy)*s,(c.z-full[4])*s)
 if nc[2]>1.355 and abs(nc[0])<.145:ids.update(p.vertices)
npts=[]
for i in ids:
 p=pts[i];npts.append(((p.x-cx)*s,(p.y-cy)*s,(p.z-full[4])*s))
print('EVAL_FULL',full,'SCALE',s,'CENTER',cx,cy)
print('NORM_HEAD_BOUNDS',(min(p[0] for p in npts),max(p[0] for p in npts),min(p[1] for p in npts),max(p[1] for p in npts),min(p[2] for p in npts),max(p[2] for p in npts)))
