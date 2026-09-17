from pathlib import Path
from collections import defaultdict, deque
import bpy

ROOT=Path('/Users/duq711gmail.com/Documents/ChatGPT/무시무시한 rpg')
bpy.ops.wm.open_mainfile(filepath=str(ROOT/'asset-staging/blender_mercenary_crossbowman_game_ready/mercenary_crossbowman_game_ready_v15.blend'))
o=bpy.data.objects['Mercenary_Clothed_Donor_LOD0']
counts=defaultdict(int)
for p in o.data.polygons:
 ids=list(p.vertices)
 for a,b in zip(ids,ids[1:]+ids[:1]): counts[tuple(sorted((a,b)))]+=1
bedges=[e for e,c in counts.items() if c==1]
adj=defaultdict(set)
for a,b in bedges: adj[a].add(b); adj[b].add(a)
unseen=set(adj)
components=[]
while unseen:
 seed=unseen.pop(); stack=[seed]; comp={seed}
 while stack:
  cur=stack.pop()
  for n in adj[cur]:
   if n not in comp:
    comp.add(n); unseen.discard(n); stack.append(n)
 components.append(comp)
print('BOUNDARY EDGES',len(bedges),'COMPONENTS',len(components))
for i,comp in enumerate(sorted(components,key=len,reverse=True)):
 pts=[o.matrix_world@o.data.vertices[j].co for j in comp]
 mins=tuple(round(min(p[k] for p in pts),4) for k in range(3)); maxs=tuple(round(max(p[k] for p in pts),4) for k in range(3))
 degrees=sorted(set(len(adj[j]) for j in comp))
 print('COMP',i,'verts',len(comp),'bounds',mins,maxs,'degrees',degrees)
