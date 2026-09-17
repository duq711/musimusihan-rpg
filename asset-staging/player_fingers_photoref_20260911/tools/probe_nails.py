import bpy,sys,json,numpy as np
from pathlib import Path
from mathutils import Vector
sys.path.insert(0,str(Path(__file__).resolve().parent))
from build_finger_detail import collect
stage=Path(__file__).resolve().parents[1];src=stage.parent/'player_fingers_detail_20260911/mac_output/iteration_10/bilateral_hands_finger_detail.blend'
bpy.ops.wm.open_mainfile(filepath=str(src));scene=bpy.data.scenes['Bilateral_Realistic_Review'];bpy.context.window.scene=scene
report={}
for side,h in collect(scene).items():
 report[side]={}
 for obj in h['objects']:
  if obj.type!='MESH' or not obj.name.startswith('Nail_'):continue
  digit=obj.name.split('_')[1].split('.')[0];m=h['holder'].matrix_world.inverted()@obj.matrix_world
  p=np.array([list(m@v.co) for v in obj.data.vertices]);obj.data.calc_loop_triangles();faces=[list(t.vertices) for t in obj.data.loop_triangles if max(t.vertices)<161]
  q=p[np.array(faces)];normal=np.cross(q[:,1]-q[:,0],q[:,2]-q[:,0]).sum(axis=0);normal/=np.linalg.norm(normal)
  rm=h['holder'].matrix_world.inverted()@h['rig'].matrix_world;axis=np.array(rm.to_3x3()@h['rig'].data.bones[digit+'2'].matrix_local.to_3x3().col[1]);axis/=np.linalg.norm(axis)
  dorsal=normal-axis*np.dot(normal,axis);dorsal/=np.linalg.norm(dorsal);cross=np.cross(axis,dorsal);origin=p[:161].mean(axis=0);rel=p[:161]-origin;u=rel@cross;v=rel@axis;z=rel@dorsal;rx=np.max(np.abs(u));ry=np.max(np.abs(v));u/=rx;v/=ry
  fits={}
  for order in [2,3,4,5]:
   powers=[(i,j) for i in range(order+1) for j in range(order+1-i)];D=np.array([u**i*v**j for i,j in powers]).T;coef=np.linalg.lstsq(D,z,rcond=None)[0];delta=D@coef-z;fits[order]={'max_m':float(abs(delta).max()),'rms_m':float(np.sqrt(np.mean(delta**2))), 'coefficients':coef.tolist()}
  report[side][digit]={'normal':normal.tolist(),'axis':axis.tolist(),'dorsal':dorsal.tolist(),'cross':cross.tolist(),'origin':origin.tolist(),'length_m':float(np.ptp(rel@axis)),'width_m':float(np.ptp(rel@cross)),'fits':fits,'points_local_frame':np.stack([rel@cross,rel@axis,z],axis=1).tolist(),'vertex0':p[0].tolist(),'nail_shell_thickness':{'min':float(np.linalg.norm(p[:161]-p[161:],axis=1).min()),'max':float(np.linalg.norm(p[:161]-p[161:],axis=1).max())}}
(stage/'audit/nail_surface_probe.json').write_text(json.dumps(report,indent=2));print('NAIL_PROBE_COMPLETE')
