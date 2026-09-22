"""Read-only full-body mesh landmarks/contours; coordinates are metres and Blender Z-up."""
from pathlib import Path
import bpy,numpy as np,json,hashlib
H=Path(__file__).resolve().parent;SOURCE=H.parent/'player_reference_anatomy_20260922/Gravebound_Reference_Anatomy.blend'
bpy.ops.wm.open_mainfile(filepath=str(SOURCE));parts={}
for o in bpy.context.scene.objects:
 if o.type!='MESH':continue
 m=o.data;a=np.empty(len(m.vertices)*3,np.float32);m.vertices.foreach_get('co',a);a=a.reshape(-1,3).astype(float);w=np.array(o.matrix_world);a=a@w[:3,:3].T+w[:3,3]
 m.calc_loop_triangles();t=np.empty(len(m.loop_triangles)*3,np.int32);m.loop_triangles.foreach_get('vertices',t);t=t.reshape(-1,3)
 edges=np.concatenate([t[:,[0,1]],t[:,[1,2]],t[:,[2,0]]]);edges=np.unique(np.sort(edges,axis=1),axis=0)
 parts[o.name]={'v':a,'e':edges,'lo':float(a[:,2].min()),'hi':float(a[:,2].max())}
def box(v):
 if not len(v):return None
 lo=v.min(axis=0);hi=v.max(axis=0);return {'min':lo.tolist(),'max':hi.tolist(),'size':(hi-lo).tolist(),'center':((hi+lo)/2).tolist()}
def sec(n,z):
 p=parts[n]
 if z<p['lo'] or z>p['hi']:return np.empty((0,3))
 a=p['v'][p['e'][:,0]];b=p['v'][p['e'][:,1]];d=b[:,2]-a[:,2];m=(np.abs(d)>1e-10)&((a[:,2]-z)*(b[:,2]-z)<=0)
 a,b,d=a[m],b[m],d[m];return a+((z-a[:,2])/d)[:,None]*(b-a)
def group_sec(names,z):return np.concatenate([sec(n,z) for n in names])
def landmark(name,position,kind,notes=''):
 return {'name':name,'position_m':list(position),'kind':kind,'notes':notes}
allnames=list(parts);limbs=['Gravebound_FP_L_Arm','Gravebound_FP_R_Arm','Gravebound_FP_L_Hand','Gravebound_FP_R_Hand'];core=[n for n in allnames if n not in limbs and not any(k in n for k in ['Pouch','Belt'])]
allv=np.concatenate([p['v'] for p in parts.values()]);out={'source':str(SOURCE),'source_sha256':hashlib.sha256(SOURCE.read_bytes()).hexdigest(),'coordinate_system':'+Z up, +Y front','world_bounds':box(allv),'mesh_bounds':{n:box(p['v']) for n,p in parts.items()},'height_sections':[],'part_sections':{},'landmarks':[],'caveat':'Mesh/clothing landmarks and documented authored guide positions, not anatomical joint fitting. No skeleton or full-body reference pixel dimensions are assumed.'}
for z in [round(x,3) for x in np.arange(.025,1.726,.025)]:
 out['height_sections'].append({'z':z,'whole_model':box(group_sec(allnames,z)),'core_without_arms_accessories':box(group_sec(core,z))})
for n in allnames:
 if any(k in n for k in ['Pouch','Belt','Eyes']):continue
 zs=np.arange(max(.025,np.ceil(parts[n]['lo']/.025)*.025),parts[n]['hi']+.00001,.025)
 out['part_sections'][n]=[{'z':round(float(z),4),**box(sec(n,z))} for z in zs if len(sec(n,z))]
head=parts['Gravebound_AnatomicalHead']['v'];out['landmarks'].append(landmark('crown',head[head[:,2].argmax()],'mesh extrema'))
headface=head[head[:,2]>=1.51];out['face_above_1_51_bounds']=box(headface)
out['landmarks'].append(landmark('chin_approx',(0,.115,1.510),'visual/profile estimate','Lower anterior face begins near Z1.510; not a landmark embedded in donor mesh.'))
# Current open neckline's top varies strongly from front to back.
torso=parts['Gravebound_QuiltedTorso']['v'];near=torso[np.abs(torso[:,0])<.075]
for key,m in [('neckline_front',near[:,1]>.025),('neckline_back',near[:,1]<-.025)]:
 q=near[m];out['landmarks'].append(landmark(key,q[q[:,2].argmax()],'local mesh extrema','Garment top, not bare-neck base.'))
for side in ['L','R']:
 arm='Gravebound_FP_'+side+'_Arm';hand='Gravebound_FP_'+side+'_Hand';h=parts[hand]['v'];a=parts[arm]['v']
 for key,z in [('shoulder_section_center',1.36),('elbow_section_center',1.1292),('distal_forearm_section_center',.94)]:
  b=box(sec(arm,z));out['landmarks'].append(landmark(side+'_'+key,b['center'],'cross-section bbox center','Shoulder/elbow are guide heights from authored sleeve design; no armature.'))
 lookup={tuple(np.round(p,5)) for p in h};shared=np.array([p for p in a if tuple(np.round(p,5)) in lookup])
 out.setdefault('wrist_join',{})[side]={'shared_vertices':len(shared),'shared_bounds':box(shared),'hand_bounds':box(h)}
 if len(shared):out['landmarks'].append(landmark(side+'_wrist_join',box(shared)['center'],'shared sleeve/hand vertices'))
 else:out['landmarks'].append(landmark(side+'_wrist_approx',box(sec(arm,.890))['center'],'cross-section at estimated cuff height'))
 out['landmarks'].append(landmark(side+'_lowest_fingertip',h[h[:,2].argmin()],'mesh extrema'))
 trousers='Gravebound_Trousers_'+side;boot='Gravebound_Boot_'+side;cuff='Gravebound_BootCuff_'+side
 for key,z in [('knee_approx',.55),('thigh_section',.75)]:
  q=sec(trousers,z);out['landmarks'].append(landmark(side+'_'+key,box(q)['center'],'cross-section bbox center','Original knee geometry region Z.50–.62 is preserved in trousers build.'))
 for key,z in [('ankle_section_approx',.15),('shin_section',.3)]:
  q=sec(boot,z);out['landmarks'].append(landmark(side+'_'+key,box(q)['center'],'cross-section bbox center','Ankle height is a clothed-boot guide, not fitted skeleton.'))
 for n,key in [(boot,'boot_top'),(boot,'sole_bottom'),(boot,'toe_front'),(cuff,'boot_cuff_top')]:
  q=parts[n]['v'];i=q[:,2].argmax() if 'top' in key else q[:,2].argmin() if 'bottom' in key else q[:,1].argmax();out['landmarks'].append(landmark(side+'_'+key,q[i],'mesh extrema'))
pants=np.concatenate([parts['Gravebound_Trousers_L']['v'],parts['Gravebound_Trousers_R']['v']]);mid=pants[np.abs(pants[:,0])<.005];out['landmarks'].append(landmark('crotch_bridge_lowest',mid[mid[:,2].argmin()],'central trousers geometry','Lowest central point within X±5mm; clothing inseam, not bare pelvis.'))
belt=parts['Gravebound_LeatherBelt']['v'];out['landmarks'].append(landmark('belt_center',box(belt)['center'],'belt bbox center'))
Hgt=out['world_bounds']['size'][2];headH=out['world_bounds']['max'][2]-1.51;out['ratios']={'height_m':Hgt,'approx_cranial_chin_length_m':headH,'approx_head_units':Hgt/headH,'crotch_height_fraction':float(mid[:,2].min()/Hgt),'belt_height_fraction':float(box(belt)['center'][2]/Hgt),'L_hand_height_fraction':float(box(parts['Gravebound_FP_L_Hand']['v'])['size'][2]/Hgt),'L_boot_y_length_fraction':float(box(parts['Gravebound_Boot_L']['v'])['size'][1]/Hgt),'boot_cuff_height_fraction':float(parts['Gravebound_BootCuff_L']['hi']/Hgt)}
(H/'current_proportions.json').write_text(json.dumps(out,indent=2)+'\n');print('FULLBODY MEASURED',json.dumps({'ratios':out['ratios'],'landmarks':out['landmarks']}),flush=True)
