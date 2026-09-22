"""Read-only world-space measurements of accepted player mesh; never saves Blender data."""
from pathlib import Path
import bpy, json, numpy as np
HERE=Path(__file__).resolve().parent
SRC=HERE.parent/'player_neck_arm_flow_20260922/Gravebound_Neck_Arm_Flow.blend'
bpy.ops.wm.open_mainfile(filepath=str(SRC))
parts={}
for o in bpy.context.scene.objects:
    if o.type!='MESH':continue
    vs=np.empty(len(o.data.vertices)*3,dtype=np.float32);o.data.vertices.foreach_get('co',vs)
    vs=vs.reshape(-1,3).astype(np.float64);mat=np.array(o.matrix_world)
    vs=vs@mat[:3,:3].T+mat[:3,3]
    o.data.calc_loop_triangles();ts=np.empty(len(o.data.loop_triangles)*3,dtype=np.int32);o.data.loop_triangles.foreach_get('vertices',ts)
    parts[o.name]=(vs,ts.reshape(-1,3))
def bbox(v):
    lo=v.min(axis=0);hi=v.max(axis=0)
    return {'min':lo.tolist(),'max':hi.tolist(),'size':(hi-lo).tolist(),'center':((hi+lo)/2).tolist()}
def section(name,z):
    vs,ts=parts[name];vv=vs[ts];mask=(vv[:,:,2].min(axis=1)<=z)&(vv[:,:,2].max(axis=1)>=z);vv=vv[mask]
    pts=[]
    for a,b in [(0,1),(1,2),(2,0)]:
        va,vb=vv[:,a],vv[:,b];dz=vb[:,2]-va[:,2]
        ok=(np.abs(dz)>1e-10)&((va[:,2]-z)*(vb[:,2]-z)<=0)
        va,vb,dz=va[ok],vb[ok],dz[ok]
        pts.append(va+((z-va[:,2])/dz)[:,None]*(vb-va))
    return np.concatenate(pts) if pts else np.empty((0,3))
names=['Gravebound_AnatomicalHead','Gravebound_QuiltedTorso','Gravebound_FP_L_Arm','Gravebound_FP_R_Arm']
report={'source':str(SRC),'coordinate_system':'+Z up, +Y face anterior','mesh_bounds':{n:bbox(v) for n,(v,t) in parts.items()},'sections':{}}
for n in names:
    zs=[round(x,3) for x in np.arange(.65,1.461,.025)] if n.endswith('_Arm') else [round(x,3) for x in np.arange(.95,1.511,.025)] if n.endswith('Torso') else [round(x,3) for x in np.arange(1.39,1.791,.01)]
    report['sections'][n]=[]
    for z in zs:
        pts=section(n,z)
        if len(pts):report['sections'][n].append({'z':z,'points':len(pts),**bbox(pts)})
report['garment_union_sections']=[]
for z in np.arange(.95,1.471,.01):
    pts=np.concatenate([section(n,z) for n in names[1:]])
    if len(pts):report['garment_union_sections'].append({'z':round(float(z),3),**bbox(pts)})
report['cross_shoulder_profiles']=[]
for z in [1.25,1.275,1.3,1.325,1.35,1.375,1.4,1.425,1.45]:
    pts=np.concatenate([section(n,z) for n in names[1:]])
    xs=np.abs(pts[:,0]);s=[]
    for x in np.arange(0,.361,.01):
        p=pts[np.abs(xs-x)<=.004]
        if len(p):s.append({'abs_x':round(float(x),3),'front_y':float(p[:,1].max()),'back_y':float(p[:,1].min()),'depth':float(np.ptp(p[:,1]))})
    report['cross_shoulder_profiles'].append({'z':z,'x_sections':s})
allv=np.concatenate([v for v,t in parts.values()]);report['all_bounds']=bbox(allv)
(HERE/'measurements.json').write_text(json.dumps(report,indent=2)+'\n')
print('MEASUREMENTS DONE',json.dumps({'all_bounds':report['all_bounds'],'mesh_bounds':{n:report['mesh_bounds'][n] for n in names}}),flush=True)
