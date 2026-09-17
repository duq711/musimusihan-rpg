"""Read-only numerical wrist centerline/compression study; does not edit assets."""
import json, math, struct
from pathlib import Path
import numpy as np
STAGE=Path(__file__).resolve().parents[1]
def unit(v): return v / np.linalg.norm(v)
def frame(a,b):
 d=unit(b-a); reference=np.array([0.,1.,0.]) if abs(d[1])<.95 else np.array([0.,0.,-1.]); x=unit(np.cross(reference,d));return np.column_stack([x,d,unit(np.cross(x,d))])
def new_fit(old):
 pivot=np.array([0.,0.,.05625]); rest=np.array([0.,0.,.26]); elbow=old[:,2]*.26
 s=np.linalg.norm(elbow-pivot)/np.linalg.norm(rest-pivot)
 B=frame(elbow,pivot)@np.diag([1,s,1])@frame(rest,pivot).T
 origin=pivot-B@pivot
 return B,origin

def curve_metrics(B,origin):
 a,b=.014,.075; span=b-a
 A=np.array([0.,0.,a]); Z=np.array([0.,0.,1.]); P=B@np.array([0.,0.,b])+origin
 d0=span*Z;d1=span*B[:,2]
 delta=P-A-d0; dd=d1-d0
 c3,c4,c5=10*delta-4*dd,-15*delta+7*dd,6*delta-3*dd
 t=np.linspace(0,1,1001)[:,None]
 C=A+d0*t+c3*t**3+c4*t**4+c5*t**5
 D=d0+3*c3*t*t+4*c4*t**3+5*c5*t**4
 DD=6*c3*t+12*c4*t*t+20*c5*t**3
 speed=np.linalg.norm(D,axis=1)
 curvature=np.linalg.norm(np.cross(D,DD),axis=1)/speed**3
 # Conservative circumradius envelope measured from the actual cuff mesh.
 radii=np.interp(a+(b-a)*t[:,0],zs,rs)
 ratio=curvature*radii
 # Smooth, curvature-driven compression in bend normal only; zero curvature =>1.
 alpha=1/np.sqrt(1+(ratio/.70)**2)
 margin=1-alpha*ratio
 result={'endpoint_separation_mm':float(np.linalg.norm(P-A)*1000),'arc_length_mm':float(np.linalg.norm(np.diff(C,axis=0),axis=1).sum()*1000),
  'min_center_speed_per_rest_z':float(speed.min()/span),'max_curvature_per_m':float(curvature.max()),
  'uncompressed_min_jacobian_bound':float((speed/span*(1-ratio)).min()),
  'compressed_min_jacobian_bound':float((alpha*speed/span*margin).min()),
  'min_bend_width_scale':float(alpha.min()),'minimum_tubular_margin':float(margin.min()),
  'bend_degrees':math.degrees(math.acos(float(unit(B[:,2])[2]))),'axial_scale':float(np.linalg.norm(B[:,2])),
  'start_center':A.tolist(),'end_center':P.tolist(),'compression_endpoints':[float(alpha[0]),float(alpha[-1])],
  'maximum_normalized_curvature_r':float(ratio.max())}
 # Tube sufficiency also needs global separation, not just positive local det.
 # This 1D proximity measure flags returning/looping centerlines conservatively.
 distances=np.linalg.norm(C[:,None,:]-C[None,:,:],axis=2)
 nonlocal_mask=np.abs(np.arange(len(C))[:,None]-np.arange(len(C))[None,:])>350
 result['minimum_center_distance_t_separation_gt_0_35_mm']=float(distances[nonlocal_mask].min()*1000)
 return result
# glTF wrist geometry in native Godot coordinate basis; authored cuff object matrix is identity.
blob=(STAGE/'mac_output/iteration_02/left_hand_wrist_refined.glb').read_bytes();length=struct.unpack_from('<I',blob,12)[0]
doc=json.loads(blob[20:20+length]);binary=20+length+8
mesh=next(m for m in doc['meshes'] if 'Wrist' in m['name'])
points=[]
for primitive in mesh['primitives']:
 acc=doc['accessors'][primitive['attributes']['POSITION']];view=doc['bufferViews'][acc['bufferView']]
 offset=binary+view.get('byteOffset',0)+acc.get('byteOffset',0);stride=view.get('byteStride',12)
 points += [struct.unpack_from('<3f',blob,offset+i*stride) for i in range(acc['count'])]
points=np.array(points); levels=sorted(set(points[:,2]));zs=np.array(levels);rs=np.array([np.linalg.norm(points[points[:,2]==z,:2],axis=1).max() for z in zs])
rows=[]
for line in (STAGE/'godot_wrist_fullfit_diagnostic02.log').read_text().splitlines():
 if 'WRIST FIT DIAGNOSTIC: ' not in line:continue
 record=json.loads(line.split('WRIST FIT DIAGNOSTIC: ',1)[1]);old=np.array(record['fit_basis']).T
 B,origin=new_fit(old)
 row={'context':record['context'],'pivot_fit_basis_columns':B.T.tolist(),'pivot_fit_origin':origin.tolist(),'quintic_centerline':curve_metrics(B,origin)}
 rows.append(row)
report={'method':'Independent NumPy evaluation, exact pivot fit reconstructed from logged elbow; quintic Hermite endpoints and first derivatives, zero endpoint second derivatives; conservative actual cuff circumradius bound',
 'formula':'C=A+D0*t+(10*delta-4*dd)*t^3+(-15*delta+7*dd)*t^4+(6*delta-3*dd)*t^5; radial compression along curvature normal only alpha=1/sqrt(1+(kappa*rmax/.70)^2)',
 'limitations':['Positive local determinant is not by itself a global self-intersection proof.','Compression bound uses circumradius, more conservative than actual bend-plane section support.','No Godot or Blender execution and no model or runtime modifications.'],'poses':rows}
(STAGE/'wrist_curve_numeric.json').write_text(json.dumps(report,indent=2))
for r in rows:print(r['context'],json.dumps(r['quintic_centerline']))
