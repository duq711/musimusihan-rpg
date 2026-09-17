"""Read-only current cuff / archived real-pose probe of the runtime start change."""
import hashlib,json,math,struct,sys
from pathlib import Path
import numpy as np
stage=Path(__file__).resolve().parents[1]
legacy=stage.parent/'player_wrist_refinement_20260910'
ns={'__name__':'probe','__file__':str(legacy/'tools/wrist_inner_curve_probe.py')}
text=(legacy/'tools/wrist_inner_curve_probe.py').read_text();exec(text[:text.index('\nrows=[]')],ns)
ns['map_kind']='rational';P=np.array([0.,0.,.05625]);E=np.array([0.,0.,1.])
def load(side):
 path=stage/f'mac_output/final_02/{side}_hand_reference.glb';blob=path.read_bytes();n=struct.unpack_from('<I',blob,12)[0];d=json.loads(blob[20:20+n]);base=20+n+8
 def acc(i):
  a=d['accessors'][i];v=d['bufferViews'][a['bufferView']];count={'VEC3':3,'SCALAR':1}[a['type']];fmt={5126:'f',5123:'H',5125:'I'}[a['componentType']];step=struct.calcsize(fmt)*count;offset=base+v.get('byteOffset',0)+a.get('byteOffset',0)
  return np.array([struct.unpack_from('<'+fmt*count,blob,offset+j*v.get('byteStride',step)) for j in range(a['count'])])
 node=next(x for x in d['nodes'] if 'WristCuff' in x.get('name','') and 'mesh'in x)
 assert not any(k in node for k in ['matrix','translation','rotation','scale'])
 points=[];faces=[];offset=0
 for primitive in d['meshes'][node['mesh']]['primitives']:
  q=acc(primitive['attributes']['POSITION']);f=acc(primitive['indices']).reshape(-1,3);points.append(q);faces.append(f+offset);offset+=len(q)
 return np.vstack(points),np.vstack(faces).astype(int),hashlib.sha256(blob).hexdigest()
def positions(points,B,start):
 span=.075-start;ease=min(.008/span,.4);t=np.clip((points[:,2]-start)/span,0,1);edge=np.minimum(t,1-t)
 w=np.where(edge<ease,edge**2/(2*ease*(1-ease)),(edge-ease*.5)/(1-ease));w=np.where(t<=.5,w,1-w)
 derivative=np.where(edge<ease,edge/(ease*(1-ease)),1/(1-ease))/span;derivative=np.where((t>0)&(t<1),derivative,0)
 scale=np.linalg.norm(B[:,2]);R=B@np.diag([1,1,1/scale]);theta=math.acos(np.clip((np.trace(R)-1)/2,-1,1));axis=ns['unit'](np.array([R[2,1]-R[1,2],R[0,2]-R[2,0],R[1,0]-R[0,1]]));bend=ns['unit'](np.cross(E,axis));power=span/(.075-P[2])
 axial=points[:,2]-P[2]+(scale-1)*(.075-P[2])*t**power;axial=np.where(t>=1,scale*(points[:,2]-P[2]),axial)
 ad=1+(scale-1)*t**(power-1);k=theta*derivative*np.linalg.norm(axis[:2])/ad
 radial=points.copy();radial[:,2]=0;inner=radial@bend;short=np.where(inner<0,inner/np.sqrt(1+(k*inner)**2),inner);radial+=(short-inner)[:,None]*bend
 radial[:,2]=axial;angle=theta*w;cos=np.cos(angle)[:,None];sin=np.sin(angle)[:,None]
 return P+radial*cos+np.cross(axis,radial)*sin+axis*np.sum(radial*axis,axis=1)[:,None]*(1-cos)
rows=[]
for line in (legacy/'godot_wrist_fullfit_diagnostic02.log').read_text().splitlines():
 if 'WRIST FIT DIAGNOSTIC: ' not in line:continue
 row=json.loads(line.split('WRIST FIT DIAGNOSTIC: ',1)[1]);side='left'if row['side']<0 else'right';points,faces,sha=load(side);B,origin=ns['fit'](np.array(row['fit_basis']).T);entry={'context':row['context'],'current_glb_sha256':sha,'archived_pose_pivot_basis_columns':B.T.tolist(),'starts':{}}
 for start in [.014,.026,.027,.028]:
  ns.update(a=start,b=.075,L=.075-start,eps=.008/(.075-start))
  metrics=ns['study'](points,faces,B,origin,True);out=positions(points,B,start);overlap=points[:,2]<=.020696754+.002
  metrics['actual_overlap_vertices']=int(overlap.sum());metrics['maximum_overlap_movement_m']=float(np.linalg.norm(out[overlap]-points[overlap],axis=1).max());entry['starts'][str(start)]=metrics
 rows.append(entry)
report={'status':'read_only_numeric_probe','runtime_formula':'Same pivot C1 axial, 8mm eased rotation, rational inside-half compression as wrist_cuff_deformer.gd', 'runtime_sha256':hashlib.sha256((stage.parents[1]/'godot-game/scripts/wrist_cuff_deformer.gd').read_bytes()).hexdigest(),'skin_max_native_godot_z':.020696754,'new_start':.028,'rigid_margin_m':.028-.020696754,'poses':rows,'limitations':['Fits are reconstructed from archived actual production-pose diagnostics with the unchanged wrist pivot, not newly captured GPU fits.','GPU visual approval remains a separate root task.']}
(stage/'diagnostics/wrist_start_metadata_grid.json').write_text(json.dumps(report,indent=2));print(json.dumps({'poses':len(rows),'old_max_overlap_movement_mm':max(r['starts']['0.014']['maximum_overlap_movement_m'] for r in rows)*1000,'new_max_overlap_movement_mm':max(r['starts']['0.028']['maximum_overlap_movement_m'] for r in rows)*1000,'new_min_jacobian':min(r['starts']['0.028']['min_jacobian'] for r in rows),'new_reversed_triangles':sum(r['starts']['0.028']['reversed_triangles'] for r in rows)}))
