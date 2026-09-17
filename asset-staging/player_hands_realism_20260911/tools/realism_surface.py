"""Submillimeter anatomical refinement and pigment masks; topology stays unchanged."""
import math
import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree
DIGITS=('thumb','index','middle','ring','little')
def smooth(a,b,v):
 t=max(0.,min(1.,(v-a)/(b-a)));return t*t*(3-2*t)
def srgb(v):return v/12.92 if v<=.04045 else ((v+.055)/1.055)**2.4
def color(c):return tuple(srgb(x)for x in c)+(1.,)
def mix(a,b,t):return tuple(x*(1-t)+y*t for x,y in zip(a,b))
def attrs(obj):
 for name in ('RealismPigment','RealismMasks'):
  old=obj.data.color_attributes.get(name)
  if old:obj.data.color_attributes.remove(old)
 return (obj.data.color_attributes.new(name='RealismPigment',type='FLOAT_COLOR',domain='POINT'),obj.data.color_attributes.new(name='RealismMasks',type='FLOAT_COLOR',domain='POINT'))
def setup_hand(skin,rig,holder,nails):
 points=[skin.matrix_world@v.co for v in skin.data.vertices];basis=skin.data.shape_keys.key_blocks['Basis'];inv=skin.matrix_world.to_3x3().inverted();normals=[(skin.matrix_world.to_3x3()@v.normal).normalized()for v in skin.data.vertices]
 names={g.index:g.name for g in skin.vertex_groups};owners=[]
 for v in skin.data.vertices:
  name=names[max(v.groups,key=lambda g:g.weight).group];owners.append(next((d for d in DIGITS if name.startswith(d)),'wrist'))
 nailpoints=[];nailfaces=[]
 for nail in nails:
  n=len(nailpoints);nailpoints.extend(nail.matrix_world@v.co for v in nail.data.vertices);nailfaces.extend(tuple(n+i for i in p.vertices)for p in nail.data.polygons)
 nailtree=BVHTree.FromPolygons(nailpoints,nailfaces)
 trimfaces=[tuple(p.vertices)for p in skin.data.polygons if all(i>=12036 for i in p.vertices)]
 trimtree=BVHTree.FromPolygons(points,trimfaces)
 frames={}
 for digit in DIGITS:
  for j in range(3):
   matrix=rig.matrix_world@rig.data.bones[digit+str(j)].matrix_local;anchor=matrix.translation;axis=matrix.to_3x3().col[1].normalized();dorsal=matrix.to_3x3().col[2].normalized();cross=axis.cross(dorsal).normalized()
   physical=[i for i in range(12036)if owners[i]==digit];near=sorted(physical,key=lambda i:abs((points[i]-anchor).dot(axis)))[:60]
   center=anchor.copy();center+=axis*(sum((points[i]-anchor).dot(axis)for i in near)/len(near))
   for direction in (cross,dorsal):
    vals=sorted((points[i]-center).dot(direction)for i in near);center+=direction*(vals[3]+vals[-4])*.5
   frames[digit,j]=(center,axis,dorsal,cross)
 pigment,masks=attrs(skin);joint_attributes=[]
 for name in ('RealismJoint1','RealismJoint2','RealismDorsal'):
  old=skin.data.attributes.get(name)
  if old:skin.data.attributes.remove(old)
  joint_attributes.append(skin.data.attributes.new(name=name,type='FLOAT_VECTOR',domain='POINT'))
 changed=[];protected=[];maxdelta=0.;creases=0;dorsum_changed=[];finger_changed=[];dorsum_max=0.
 for v,point,normal,owner in zip(skin.data.vertices,points,normals,owners):
  native=holder.matrix_world.inverted()@point;crease=0.;redness=0.;amount=0.
  for j,attribute in enumerate(joint_attributes[:2],1):
   if owner!='wrist':
    center,axis,dorsal,cross=frames[owner,j];offset=point-center;attribute.data[v.index].vector=(offset.dot(cross),offset.dot(axis),0.)
   else:attribute.data[v.index].vector=(1.,1.,1.)
  joint_attributes[2].data[v.index].vector=frames[owner,1][2]if owner!='wrist'else(0.,0.,1.)
  if owner!='wrist':
   for j in range(3):
    center,axis,dorsal,cross=frames[owner,j];d=point-center;along=d.dot(axis);radial=(d-axis*along).length;gate=math.exp(-(radial/.025)**4);face=normal.dot(dorsal)
    outer=max(0,face)**2;inner=max(0,-face)**2
    width=.0044 if j else .006
    volume=(.00072 if j else .00032)*math.exp(-(along/width)**2)*outer
    fold=math.exp(-((along-.001)/.0010)**2)+.40*math.exp(-((along+.0023)/.0008)**2)
    amount+=gate*(volume-.00019*fold*(.6*outer+inner))
    crease=max(crease,min(1,gate*fold*(.6*outer+inner)))
    redness=max(redness,gate*math.exp(-(along/.008)**2)*(.3+.7*abs(face)))
  elif native.y>.012 and normal.z>.30:
   for digit in ('index','middle','ring','little'):
    end,axis,unused,cross=frames[digit,0];start=end-axis*.055;segment=end-start;segment.z=0;offset=point-start;offset.z=0;t=max(0,min(1,offset.dot(segment)/segment.length_squared));distance=(offset-segment*t).length
    amount+=.00038*math.exp(-(distance/.0035)**2)*math.sin(math.pi*t)*normal.z**2
  nearest=nailtree.find_nearest(point);nail_distance=nearest[3] if nearest[0]is not None else 1.
  trim=trimtree.find_nearest(point);trim_distance=trim[3]if trim[0]is not None else 1.
  guard=smooth(.0015,.006,nail_distance)*smooth(.010,.020,native.y)*smooth(.0006,.0025,trim_distance)
  if native.y<=.010 or nail_distance<=.0015 or v.index>=12036:protected.append(v.index);guard=0.
  amount=max(-.00065,min(.00065,amount))*guard
  if abs(amount)>1e-8:
   original=basis.data[v.index].co.copy();delta=inv@(normal*amount)
   for key in skin.data.shape_keys.key_blocks:key.data[v.index].co+=delta
   v.co=basis.data[v.index].co;changed.append(v.index);maxdelta=max(maxdelta,abs(amount))
   if owner=='wrist':dorsum_changed.append(v.index);dorsum_max=max(dorsum_max,abs(amount))
   else:finger_changed.append(v.index)
  # Pigment is a field in the surface, independent of lighting and SSS.
  palm=max(0,-normal.z);base=mix((.565,.392,.291),(.615,.445,.350),palm*.48)
  base=mix(base,(.565,.330,.272),redness*.17)
  pigment.data[v.index].color=color(base);masks.data[v.index].color=(crease,redness,max(0,normal.z)*redness,1)
  creases+=crease>.2
 skin.data.update()
 return {'changed_vertex_indices':changed,'protected_vertex_indices':protected,'changed_vertices':len(changed),'maximum_displacement_m':maxdelta,'dorsum_changed_vertices':len(dorsum_changed),'dorsum_maximum_displacement_m':dorsum_max,'finger_changed_vertices':len(finger_changed),'crease_mask_vertices':creases,'native_blender_y_protected_max':.010,'nail_protection_radius_m':.0015,'nail_transition_end_m':.006,'maximum_allowed_sculpt_m':.00065,'wrist_cuff_forearm_geometry_changed':False,'skin_section_landmarks':{d+'_'+str(j):list(holder.matrix_world.inverted()@f[0])for(d,j),f in frames.items()},'changed_native_bounds':[[min((holder.matrix_world.inverted()@points[i])[k]for i in changed),max((holder.matrix_world.inverted()@points[i])[k]for i in changed)]for k in range(3)]}
def setup_part(obj,rig=None):
 pigment,masks=attrs(obj)
 nail='Nail_'in obj.name
 if nail:
  digit=next(d for d in DIGITS if d in obj.name);m=rig.matrix_world@rig.data.bones[digit+'2'].matrix_local;axis=m.to_3x3().col[1].normalized();coords=[(obj.matrix_world@v.co-m.translation).dot(axis)for v in obj.data.vertices];lo,hi=min(coords),max(coords)
 for v in obj.data.vertices:
  if nail:
   t=(coords[v.index]-lo)/(hi-lo);tip=smooth(.77,.90,t);bed=mix((.610,.418,.348),(.710,.617,.480),tip);lunula=math.exp(-((t-.19)/.10)**2)*.20;bed=mix(bed,(.68,.56,.46),lunula);pigment.data[v.index].color=color(bed);masks.data[v.index].color=(0,tip,0,1)
  else:pigment.data[v.index].color=color((.13,.10,.075));masks.data[v.index].color=(0,0,1 if 'Forearm'in obj.name else 0,1)
