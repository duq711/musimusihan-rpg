import sys,json,math,hashlib
from pathlib import Path
import bpy,numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree
from mathutils.geometry import intersect_ray_tri
sys.path.insert(0,'tools/dcc')
from labrador_pet import set_action
from labrador_pet_validate import coordinates,pose
from labrador_pet_preview import stage
rig=bpy.data.objects['LabradorPet'];mesh=bpy.data.objects['LabradorPet_Mesh'];scene=bpy.context.scene
mesh.data.calc_loop_triangles();tri=np.asarray([list(t.vertices) for t in mesh.data.loop_triangles],dtype=int)
weights=np.zeros((len(mesh.data.vertices),len(mesh.vertex_groups)))
for v in mesh.data.vertices:
 for g in v.groups:weights[v.index,g.group]=g.weight
body=[g.index for g in mesh.vertex_groups if g.name.startswith(('Torso','Back_'))]
regions={'chest':weights[:,body].sum(axis=1)}
for n in ['FrontShoulder.L_18','FrontUpperLeg.L_17','FrontLowerLeg.L_16','FrontShoulder.R_21','FrontUpperLeg.R_20','FrontLowerLeg.R_19']:regions[n]=weights[:,mesh.vertex_groups[n].index]
bodyfaces=np.flatnonzero(regions['chest'][tri].mean(axis=1)>.55)
legfaces={n:np.flatnonzero(w[tri].mean(axis=1)>.55) for n,w in regions.items() if n!='chest'}

def intersections(world,fa,fb):
 va=[Vector(v) for v in world];aa=BVHTree.FromPolygons(va,[list(tri[i]) for i in fa],all_triangles=True);bb=BVHTree.FromPolygons(va,[list(tri[i]) for i in fb],all_triangles=True)
 hits=[]
 for ia,ib in aa.overlap(bb):
  a=tri[fa[ia]];b=tri[fb[ib]]
  if set(a)&set(b):continue
  points=[]
  for first,second in ((a,b),(b,a)):
   for j in range(3):
    origin=va[first[j]];direction=va[first[(j+1)%3]]-origin
    if direction.length<1e-8:continue
    point=intersect_ray_tri(va[second[0]],va[second[1]],va[second[2]],direction,origin,True)
    if point is not None:
     t=(point-origin).dot(direction)/direction.length_squared
     if .000001<t<.999999:points.append(point)
  if len(points)>=2 and max((a-b).length for a in points for b in points)>1e-5:hits.append((int(fa[ia]),int(fb[ib]),[list(v) for v in points[:2]]))
 return hits
out={'asset_sha256':hashlib.sha256(Path('asset-staging/labrador-sprint-20261006/production/LabradorPet_Sprint.blend').read_bytes()).hexdigest(),'poses':{}}
worlds={}
for label,action,frame in [('neutral','IdleFriendly',1),('phase_090','Run',38.8)]:
 set_action(rig,bpy.data.actions[action]);matrices=pose(rig,frame);world=coordinates(mesh);worlds[label]=world
 row={'intersections':{},'region_ranges':{}}
 for n,faces in legfaces.items():
  hit=intersections(world,bodyfaces,faces);row['intersections'][n]={'exact_edge_triangle_crossings':len(hit),'examples':hit[:2]}
  inds=np.flatnonzero(regions[n]>.7);v=world[inds];row['region_ranges'][n]={'vertices':len(inds),'minimum':v.min(axis=0).tolist() if len(v) else None,'maximum':v.max(axis=0).tolist() if len(v) else None}
 out['poses'][label]=row
areas={}
for n,faces in legfaces.items():
 vals=[]
 for label in ('neutral','phase_090'):
  v=worlds[label][tri[faces]];vals.append(np.linalg.norm(np.cross(v[:,1]-v[:,0],v[:,2]-v[:,0]),axis=1)/2)
 ratio=vals[1]/np.maximum(vals[0],1e-12)
 if not len(ratio):continue
 areas[n]={'triangles':len(faces),'area_ratio_min':float(ratio.min()),'area_ratio_p05':float(np.quantile(ratio,.05)),'triangles_under_20percent_neutral_area':int((ratio<.2).sum())}
out['triangle_skin_area']=areas
outdir=Path('/tmp/labrador-sprint-readonly-diagnosis');outdir.mkdir(exist_ok=True);(outdir/'diagnosis.json').write_text(json.dumps(out,indent=2)+'\n');print('READONLY_SKIN_DIAGNOSIS',json.dumps(out))
camera=stage(scene);camera.location=(2.1,0,.53);camera.rotation_euler=(Vector((0,0,.40))-camera.location).to_track_quat('-Z','Y').to_euler();camera.data.ortho_scale=2.3;scene.render.resolution_x=900;scene.render.resolution_y=550;scene.eevee.taa_render_samples=16
for label,action,frame in [('neutral','IdleFriendly',1),('phase_090','Run',38.8)]:
 set_action(rig,bpy.data.actions[action]);pose(rig,frame);scene.render.filepath=str(outdir/(label+'.png'));bpy.ops.render.render(write_still=True)
print('READONLY_RENDER_READY',outdir)
