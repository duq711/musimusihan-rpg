"""Supplement fixed hand-facing comparisons with actual intrinsic thumb faces."""
import argparse,json,math,hashlib
from pathlib import Path
import numpy as np
p=argparse.ArgumentParser();p.add_argument('--candidate',required=True);a=p.parse_args()
stage=Path(__file__).resolve().parents[1];model=stage/'mac_output'/a.candidate
manifest=json.loads((stage/'audit/individual_render_probe03/render_report.json').read_text())
roll=json.loads((model/'thumb_rotation_report.json').read_text())['hands']['left']
u=np.array(roll['axis_native']);origin=np.array(roll['pivot_native']);angle=math.radians(roll['angle_degrees'])
cross=np.array([[0,-u[2],u[1]],[u[2],0,-u[0]],[-u[1],u[0],0]])
rotation=np.eye(3)*math.cos(angle)+(1-math.cos(angle))*np.outer(u,u)+math.sin(angle)*cross
for key in ['thumb_dorsal','thumb_palmar']:
    frame=manifest['frames'][key]
    for name in ['location_native','center_native','base_native','tip_bone_native']:
        frame[name]=(origin+rotation@(np.array(frame[name])-origin)).tolist()
    for name in ['axis_native','dorsal_native']:frame[name]=(rotation@np.array(frame[name])).tolist()
    frame['rotation_native']=(rotation@np.array(frame['rotation_native'])).tolist()
    for light in frame['lights']:
        for name in ['location_native','target_native']:
            light[name]=(origin+rotation@(np.array(light[name])-origin)).tolist()
manifest['purpose']='Supplemental intrinsic thumb dorsal/palmar cameras after actual axial rotation; the ten fixed hand-facing comparison cameras remain separate and unchanged.'
manifest['frames_sha256']=hashlib.sha256(json.dumps(manifest['frames'],sort_keys=True).encode()).hexdigest()
target=model/'thumb_local_camera_manifest.json';assert not target.exists();target.write_text(json.dumps(manifest,indent=2))
print(target)
