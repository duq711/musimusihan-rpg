from pathlib import Path
import json,sys,math
import numpy as np
s=Path(__file__).resolve().parents[1];root=s.parents[1];d=json.loads((s/'audit/fitted_pose_03.json').read_text());q=np.array(d['parameters'])
r=json.loads((root/'godot-game/artifacts/visual_qa/torch_grip/baseline_01/geometry.json').read_text())
C=np.array([[1,0,0],[0,0,1],[0,-1,0.]])
old=np.array(r['arm_in_torch'][:3]).T
angle=np.radians(90);Y=np.array([[np.cos(angle),0,np.sin(angle)],[0,1,0],[-np.sin(angle),0,np.cos(angle)]])
t=-q[18];Z=np.array([[np.cos(t),-np.sin(t),0],[np.sin(t),np.cos(t),0],[0,0,1.]])
R=Y@old@C@Z;center=np.array(d['shaft_in_hand']['center']);offset=np.array([0,.019,-.0035]);basis=R@C.T;origin=np.array([0,.12,0])-R@center-basis@offset
v=lambda x:'Vector3('+', '.join(format(float(a),'.12g') for a in x)+')'
text='extends RefCounted\n## Authored against the actual 74%-scale torch shaft and supplied left hand.\n## Signed additions account for the source hand already being curled.\n'
text+='const ARM_TRANSFORM := Transform3D(Basis('+', '.join(v(c) for c in basis.T)+'), '+v(origin)+')\n'
text+='const CONTACT_CENTER := '+v(offset+C@center)+'\n'
text+='const THUMB_OPPOSITION := '+str(float(q[15]))+'\nconst JOINT_ANGLES := {\n'
for i,name in enumerate(['thumb','index','middle','ring','little']):text+='\t"'+name+'": '+v(q[i*3:i*3+3])+',\n'
text+='}\n'
(root/'godot-game/scripts/torch_grip_pose.gd').write_text(text)
d['arm_transform_godot']=[*basis.T.tolist(),origin.tolist()];d['around_shaft_degrees']=90
(s/'mac_output/torch_grip_pose.json').write_text(json.dumps(d,indent=2))
print(text)
