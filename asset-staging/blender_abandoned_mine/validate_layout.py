"""Check the traced source before Blender builds the expensive rock meshes."""
import json, math
from pathlib import Path
D=json.loads(Path(__file__).with_name("layout.json").read_text())
def dot(a,b):return a[0]*b[0]+a[1]*b[1]
def sub(a,b):return (a[0]-b[0],a[1]-b[1])
def cross(a,b):return a[0]*b[1]-a[1]*b[0]
def pd(p,a,b):
    v=sub(b,a);w=sub(p,a);t=max(0,min(1,dot(w,v)/max(dot(v,v),1e-14)))
    return math.hypot(p[0]-a[0]-v[0]*t,p[1]-a[1]-v[1]*t)
def inside(p,poly):
    odd=False
    for a,b in zip(poly,poly[1:]+poly[:1]):
        if (a[1]>p[1])!=(b[1]>p[1]) and p[0]<(b[0]-a[0])*(p[1]-a[1])/(b[1]-a[1])+a[0]:odd=not odd
    return odd
def intersects(a,b,c,d):
    return cross(sub(b,a),sub(c,a))*cross(sub(b,a),sub(d,a))<0 and cross(sub(d,c),sub(a,c))*cross(sub(d,c),sub(b,c))<0
def sd(a,b,c,d):
    if intersects(a,b,c,d):return 0
    return min(pd(a,c,d),pd(b,c,d),pd(c,a,b),pd(d,a,b))
fail=[]
for r in D['rooms']:
    if not inside(r['center'],r['polygon']):fail.append(('center',r['id']))
    edges=list(zip(r['polygon'],r['polygon'][1:]+r['polygon'][:1]))
    for i,(a,b) in enumerate(edges):
        for j,(c,d) in enumerate(edges):
            if abs(i-j)>1 and {i,j}!={0,len(edges)-1} and intersects(a,b,c,d):fail.append(('self intersection',r['id'],i,j))
for route in D['corridors']:
    for a,b in zip(route['points'],route['points'][1:]):
        for island in D['islands']:
            poly=island['polygon'];distance=min(sd(a,b,c,d) for c,d in zip(poly,poly[1:]+poly[:1]))
            if distance<1.3 or inside(a,poly) or inside(b,poly):fail.append(('island route',route['id'],island['id'],round(distance,2)))
    for landmark in D['landmarks']:
        if landmark['type']!='stone_pillar':continue
        p=[landmark['position'][0],landmark['position'][2]]
        distance=min(pd(p,a,b) for a,b in zip(route['points'],route['points'][1:]))
        if distance<1.5:fail.append(('pillar route',route['id'],landmark['id'],round(distance,2)))
for kind,items in D['gameplay'].items():
    for item in items:
        p=[item['position'][0],item['position'][2]];r=next(r for r in D['rooms'] if r['id']==item['room_id']);poly=r['polygon']
        distance=min(pd(p,a,b) for a,b in zip(poly,poly[1:]+poly[:1]))
        if not inside(p,poly) or distance<.85:fail.append(('gameplay edge',kind,item['id'],round(distance,2)))
seen={'entrance'}
for _ in D['rooms']:
    for c in D['corridors']:
        if c['from'] in seen or c['to'] in seen:seen.update([c['from'],c['to']])
if len(seen)!=len(D['rooms']):fail.append(('disconnected',set(r['id'] for r in D['rooms'])-seen))
for f in sorted(set(fail)):print(*f)
print('Source plan:',len(D['rooms']),'chambers;',len(D['corridors']),'paths;',len(set(fail)),'issues')
raise SystemExit(bool(fail))
