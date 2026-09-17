import bpy
from pathlib import Path
from collections import defaultdict

root = Path('/Users/duq711gmail.com/Documents/ChatGPT/무시무시한 rpg')
source = root / 'asset-staging/blender_mercenary_crossbowman_game_ready/mercenary_crossbowman_game_ready_v16j_darkbrown_hair_candidate.blend'
bpy.ops.wm.open_mainfile(filepath=str(source))
obj = bpy.data.objects['Mercenary_Clothed_Donor_LOD0']
edge_faces = defaultdict(list)
for poly in obj.data.polygons:
    ids = list(poly.vertices)
    for a,b in zip(ids, ids[1:]+ids[:1]):
        edge_faces[tuple(sorted((a,b)))].append(poly.index)
boundary = [edge for edge, faces in edge_faces.items() if len(faces)==1]
adj = defaultdict(set)
for a,b in boundary:
    adj[a].add(b); adj[b].add(a)
unseen=set(adj)
loops=[]
while unseen:
    seed=unseen.pop(); stack=[seed]; comp={seed}
    while stack:
        cur=stack.pop()
        for n in adj[cur]:
            if n in unseen:
                unseen.remove(n); comp.add(n); stack.append(n)
    loops.append(comp)
print('BOUNDARY_EDGES', len(boundary), 'COMPONENTS', len(loops))
for i, comp in enumerate(sorted(loops, key=lambda c:-len(c))[:80]):
    coords=[obj.data.vertices[v].co for v in comp]
    mn=[min(c[j] for c in coords) for j in range(3)]
    mx=[max(c[j] for c in coords) for j in range(3)]
    if mx[2] > 1.20:
        print('LOOP',i,'N',len(comp),'MIN',tuple(round(x,4) for x in mn),'MAX',tuple(round(x,4) for x in mx))

main = max(loops, key=len)
print('MAIN_DEGREES', sorted({len(adj[v]) for v in main}))
start = next(iter(main))
ordered=[start]
prev=None
cur=start
for _ in range(len(main)+2):
    choices=[v for v in adj[cur] if v != prev]
    if not choices: break
    nxt=choices[0]
    if nxt == start: break
    ordered.append(nxt)
    prev,cur=cur,nxt
print('ORDERED',len(ordered))
for side, sign in [('POS',1),('NEG',-1)]:
    mask=[sign*obj.data.vertices[v].co.x > 0.12 and obj.data.vertices[v].co.z > 1.40 for v in ordered]
    runs=[]; run=[]
    for v,ok in zip(ordered,mask):
        if ok: run.append(v)
        elif run: runs.append(run); run=[]
    if run:runs.append(run)
    for i,run in enumerate(runs):
        cs=[obj.data.vertices[v].co for v in run]
        mn=[min(c[j] for c in cs) for j in range(3)]
        mx=[max(c[j] for c in cs) for j in range(3)]
        print('RUN',side,i,'N',len(run),'MIN',tuple(round(x,4) for x in mn),'MAX',tuple(round(x,4) for x in mx))
