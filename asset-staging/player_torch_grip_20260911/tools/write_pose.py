from pathlib import Path
import json,sys,math
import numpy as np
s=Path(__file__).resolve().parents[1];root=s.parents[1];d=json.loads((s/'audit/fitted_pose_04.json').read_text());q=np.array(d['parameters'])
r=json.loads((root/'godot-game/artifacts/visual_qa/torch_grip/baseline_01/geometry.json').read_text())
C=np.array([[1,0,0],[0,0,1],[0,-1,0.]])
old=np.array(r['arm_in_torch'][:3]).T
# Choose carry roll by forearm-to-wrist alignment, never finger visibility.
t=-q[18];Z=np.array([[np.cos(t),-np.sin(t),0],[np.sin(t),np.cos(t),0],[0,0,1.]])
center=np.array(d['shaft_in_hand']['center']);offset=np.array([0,.019,-.0035])
def euler(x,y,z):
 x,y,z=np.radians([x,y,z]);Rx=np.array([[1,0,0],[0,np.cos(x),-np.sin(x)],[0,np.sin(x),np.cos(x)]]);Ry=np.array([[np.cos(y),0,np.sin(y)],[0,1,0],[-np.sin(y),0,np.cos(y)]]);Rz=np.array([[np.cos(z),-np.sin(z),0],[np.sin(z),np.cos(z),0],[0,0,1]])
 return Ry@Rx@Rz
P=euler(-25,8,13);pos=np.array([-.40,-.46,-.62]);shoulder=np.array([-.29,-.34,.10]);pole=np.array([-.65,-.85,.14])
def frame(angle):
 Y=np.array([[np.cos(angle),0,np.sin(angle)],[0,1,0],[-np.sin(angle),0,np.cos(angle)]])
 R=Y@old@C@Z;basis=R@C.T;origin=np.array([0,.12,0])-R@center-basis@offset
 wrist=P@origin+pos;axis=wrist-shoulder;reach=np.linalg.norm(axis);direction=axis/reach;perp=pole-direction*np.dot(pole,direction);perp/=np.linalg.norm(perp)
 elbow=shoulder+axis*.52+perp*np.clip(.23-(reach-.4)*.34,.045,.23)
 forearm=elbow-wrist;forearm/=np.linalg.norm(forearm)
 return np.dot(P@basis[:,2],forearm),basis,origin
angle=max(np.linspace(-np.pi,np.pi,1441),key=lambda a:frame(a)[0]);alignment,basis,origin=frame(angle)
print('WRIST_ALIGNMENT_DEGREES',np.degrees(np.arccos(np.clip(alignment,-1,1))),'CARRY',np.degrees(angle))
v=lambda x:'Vector3('+', '.join(format(float(a),'.12g') for a in x)+')'
text='extends RefCounted\n## Authored against the actual 74%-scale torch shaft and supplied left hand.\n## Signed additions account for the source hand already being curled.\n'
text+='const ARM_TRANSFORM := Transform3D(Basis('+', '.join(v(c) for c in basis.T)+'), '+v(origin)+')\n'
text+='const CONTACT_CENTER := '+v(offset+C@center)+'\n'
text+='const THUMB_OPPOSITION := '+str(float(q[15]))+'\nconst JOINT_ANGLES := {\n'
for i,name in enumerate(['thumb','index','middle','ring','little']):text+='\t"'+name+'": '+v(q[i*3:i*3+3])+',\n'
text+='}\n'
text+='const ROOT_ADDUCTION := '+str(d['root_adduction_radians']).replace("'", '"')+'\n'
(root/'godot-game/scripts/torch_grip_pose.gd').write_text(text)
d['arm_transform_godot']=[*basis.T.tolist(),origin.tolist()];d['around_shaft_degrees']=float(np.degrees(angle));d['neutral_wrist_angle_degrees']=float(np.degrees(np.arccos(np.clip(alignment,-1,1))))
(s/'mac_output/torch_grip_pose.json').write_text(json.dumps(d,indent=2))
print(text)
