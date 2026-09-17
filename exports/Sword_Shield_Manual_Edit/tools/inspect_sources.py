import bpy,json
from pathlib import Path
root=Path('/Users/duq711gmail.com/Documents/ChatGPT/무시무시한 rpg')
bpy.ops.wm.open_mainfile(filepath=str(root/'asset-staging/sword_hold_long_grip_integration/source/model/SwordHold_Static.blend'))
for o in bpy.context.scene.objects:
 if o.type=='MESH':
  print('MESH',o.name,len(o.data.vertices),[g.name for g in o.vertex_groups],[(m.name,m.type) for m in o.modifiers])
  if 'Glove' in o.name:
   adj={i:[] for i in range(len(o.data.vertices))}
   for e in o.data.edges:a,b=e.vertices;adj[a].append(b);adj[b].append(a)
   unseen=set(adj);components=[]
   while unseen:
    stack=[unseen.pop()];part=[]
    while stack:
     i=stack.pop();part.append(i)
     for j in adj[i]:
      if j in unseen:unseen.remove(j);stack.append(j)
    co=[o.data.vertices[i].co for i in part]
    components.append({'n':len(part),'center':[sum(v[j] for v in co)/len(co) for j in range(3)],'min':[min(v[j] for v in co) for j in range(3)],'max':[max(v[j] for v in co) for j in range(3)]})
   print('COMPONENTS',json.dumps(sorted(components,key=lambda p:-p['n'])[:25]))
print('RIGS',[(o.name,len(o.data.bones)) for o in bpy.data.objects if o.type=='ARMATURE'])
