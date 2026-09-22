from pathlib import Path
import bpy,sys,json,hashlib,shutil,math,numpy as np
from mathutils import Vector,Matrix
HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[1];sys.path.insert(0,str(HERE))
import deformation as fit
SOURCE=HERE.parent/'player_reference_anatomy_20260922/Gravebound_Reference_Anatomy.blend'
bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
objects=[o for o in bpy.context.scene.objects if o.type=='MESH']
points={o.name:[o.matrix_world@v.co for v in o.data.vertices] for o in objects}
legparts=[o for o in objects if any(t in o.name for t in ['Trousers','Boot'])]
triangles=[]
for o in legparts:
 o.data.calc_loop_triangles()
 array=np.array(points[o.name]);triangles.extend(array[[tuple(t.vertices) for t in o.data.loop_triangles]])
triangles=np.array(triangles)
for sign in [-1.,1.]:
 pts=[v for o in legparts for v in points[o.name] if v.x*sign>0]
 centers=[];widths=[]
 for z in [.015,.03,.05,.08,.10,.13,.17,.22,.28,.35,.42,.465,.50,.55,.60,.65,.70,.75,.79,.80,.805,.810,.813,.8148,.8152,.816,.82,.85,.88]:
  # Intersect triangles with the exact horizontal plane. A 12mm vertex
  # sampling slab incorrectly mixes the crotch bridge and separated thighs.
  cross=triangles[(triangles[:,:,2].min(axis=1)<=z)&(triangles[:,:,2].max(axis=1)>=z)]
  xs=[]
  for a,b in [(0,1),(1,2),(2,0)]:
   pa=cross[:,a];pb=cross[:,b];dz=pb[:,2]-pa[:,2]
   valid=(abs(dz)>1e-10)&((pa[:,2]-z)*(pb[:,2]-z)<=0)
   hit=pa[valid]+(pb[valid]-pa[valid])*((z-pa[valid,2])/dz[valid])[:,None]
   xs.extend(abs(hit[hit[:,0]*sign>0,0]))
  if not len(xs):continue
  centers.append((z,float((max(xs)+min(xs))/2)));widths.append((z,float(max(xs)-min(xs))))
 fit.LEG_SOURCE[sign]=(fit.Curve(centers),fit.Curve(widths))
# Symmetric average of front-view inner/outer lower-limb contours.
scale=1.712215677/1365;sole=.0076724137;center=533.5
profile=[(1390,292,371,688,772),(1360,303,404,661,762),(1320,331,402,664,733),(1280,336,410,658,726),(1220,335,426,649,721),(1160,339,429,634,724),(1100,341,443,618,720),(1060,347,452,616,714),(1020,344,468,601,716),(970,349,479,580,707),(920,354,498,570,711),(860,357,510,556,712),(810,362,525,542,706),(785,367,529,538,704)]
cs=[];ws=[]
for y,l0,l1,r0,r1 in profile:
 z=sole+(1401-y)*scale
 c=((center-(l0+l1)/2)+((r0+r1)/2-center))/2*scale
 w=((l1-l0)+(r1-r0))/2*scale
 cs.append((z,c));ws.append((z,w))
fit.LEG_TARGET_CENTER=fit.Curve(cs);fit.LEG_TARGET_WIDTH=fit.Curve(ws)
report={'source':str(SOURCE.relative_to(ROOT)),'parts':{},'calibration':{'sole_z':sole,'scale_m_per_px':scale,'estimated_skull_y':36,'reference_sole_y':1401},'leg_source':{str(k):{'centers':list(zip(a.x,a.y)),'widths':list(zip(b.x,b.y))} for k,(a,b) in fit.LEG_SOURCE.items()}}
for o in objects:
 me=o.data;world=o.matrix_world.copy();inv=world.inverted();nw=world.to_3x3().inverted().transposed();nl=world.to_3x3().transposed()
 fn=fit.leg if o in legparts else fit.arm if o.name.startswith('Gravebound_FP_') else fit.torso if o.name=='Gravebound_QuiltedTorso' else fit.body
 old=points[o.name];normals=[n.vector.copy() for n in me.corner_normals];jac={};minj=10.;changed=0
 for i,p in enumerate(old):
  q=fn(p);columns=[]
  for axis in range(3):
   d=Vector();d[axis]=.00002;columns.append((fn(p+d)-fn(p-d))/.00004)
  j=Matrix(columns).transposed();det=j.determinant();minj=min(minj,det)
  if det<=.055:raise RuntimeError((o.name,tuple(p),det))
  jac[i]=j.inverted().transposed();me.vertices[i].co=inv@q;changed+=(q-p).length>1e-7
 me.update();me.normals_split_custom_set([(nl@jac[l.vertex_index]@nw@n).normalized() for l,n in zip(me.loops,normals)])
 report['parts'][o.name]={'vertices':len(me.vertices),'changed':changed,'min_jacobian':minj}
 o['proportion_revision']='Calibrated four-view full-body proportions'
bpy.context.preferences.filepaths.save_version=0
bpy.ops.object.select_all(action='SELECT');bpy.context.view_layer.objects.active=bpy.data.objects['GraveboundPlayer']
bpy.ops.wm.save_as_mainfile(filepath=str(HERE/'Gravebound_Multiview_Proportions.blend'),compress=True)
out=HERE/'gravebound_player_multiview_proportions.glb'
bpy.ops.export_scene.gltf(filepath=str(out),export_format='GLB',use_selection=True,export_animations=False,export_skins=False,export_extras=True,export_tangents=True,export_yup=True)
report['glb_sha256']=hashlib.sha256(out.read_bytes()).hexdigest();(HERE/'build_report.json').write_text(json.dumps(report,indent=2)+'\n')
shutil.copy2(out,ROOT/'godot-game/assets/3d/player/gravebound_player.glb')
print('MULTIVIEW BUILD PASS',report['glb_sha256'])
