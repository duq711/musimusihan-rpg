#!/usr/bin/env python3
"""Author 16 distinct equal-time gallop SVG pose controls, never final dog art.

This tool writes SVG/JSON text only. All raster dog photographs must be made
separately with the built-in image generator. Controls are art directions,
not measured motion capture or certification of the generated photographs.
"""
from __future__ import annotations
import argparse
import copy
import importlib.util
import json
import math
from pathlib import Path
import xml.etree.ElementTree as ET

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('border_collie_v2_controls', HERE / 'border_collie_run_v2_guides.py')
v2 = importlib.util.module_from_spec(spec)
spec.loader.exec_module(v2)
COUNT, PERIOD = 16, 42.0
WIDTH, HEIGHT, FLOOR = 1536, 1024, 850.0
PAWS = copy.deepcopy(v2.PAWS)
# The compact flight must actively gather, then lower the hind feet, rather
# than leaving the same curled silhouette parked through many phase slots.
PAWS['near_hind']['x'] = [(0,910),(2,950),(5,1000),(11,1210),(17,1295),(23,1100),(32,980),(36,870),(38,835),(40,860),(42,910)]
PAWS['near_hind']['y'] = [(0,780),(5,850),(11,850),(17,720),(23,720),(32,780),(36,715),(38,710),(40,745),(42,780)]
PAWS['far_hind']['x'] = [(0,840),(2,860),(7,965),(13,1175),(17,1290),(23,1140),(32,1000),(36,870),(38,820),(40,810),(42,840)]
PAWS['far_hind']['y'] = [(0,765),(7,850),(13,850),(17,755),(23,700),(32,755),(36,705),(38,705),(40,735),(42,765)]

def frame_data(index):
    t = (17 + (index-1)*PERIOD/COUNT) % PERIOD
    dy = v2.curve(t, v2.BODY_Y)
    pitch_deg = v2.curve(t, v2.BODY_PITCH)
    pitch = math.radians(pitch_deg)
    tf = lambda p: v2.transform(p, dy, pitch)
    # Roots are inside the shoulder/pelvic volumes; the silhouette hides the
    # proximal portions. Low surface roots caused the v2 elbows to approach
    # the floor and made lower forelimbs look like right-angle rods.
    roots = {'near_fore': tf((600,520)), 'far_fore': tf((616,510)),
             'near_hind': tf((1020,535)), 'far_hind': tf((1036,525))}
    legs = {}
    for name, paw_spec in PAWS.items():
        start, finish = paw_spec['contact']
        paw = (v2.curve(t, paw_spec['x'], {start:35.0, finish:35.0}),
               v2.curve(t, paw_spec['y'], {start:0.0, finish:0.0}))
        root = roots[name]
        if 'fore' in name:
            joint, over, under = v2.two_link(root, paw, 165, 265, 'caudal_elbow')
            points = {'shoulder':root, 'elbow':joint, 'paw':paw}
            lengths = [165,265]
        else:
            angle = math.radians(v2.curve(t, paw_spec['hock_angle']))
            hock = (paw[0]+90*math.cos(angle), paw[1]+90*math.sin(angle))
            joint, over, under = v2.two_link(root, hock, 170, 160, 'cranial_stifle')
            points = {'hip':root, 'stifle':joint, 'hock':hock, 'paw':paw}
            lengths = [170,160,90]
        legs[name] = {'contact':start <= t < finish,
                      'joints':{k:[round(q[0],4),round(q[1],4)] for k,q in points.items()},
                      'segment_lengths_px':lengths,
                      'unreachable_extension_px':round(over,4),
                      'unreachable_fold_px':round(under,4)}
    data = v2.frame_data(t)
    data.update({'frame':index, 'control_phase_t':round(t,6),
                 'time_seconds':round((index-1)*0.7/COUNT,6),
                 'cycle_phase':round((index-1)/COUNT,8),
                 'gait_phase':round(t/PERIOD,8), 'legs':legs})
    data['body_points']['shoulder'] = legs['near_fore']['joints']['shoulder']
    data['body_points']['hip'] = legs['near_hind']['joints']['hip']
    data['art_control_notes'] = ['Dominant full-body filled pose/layout reference; no prior whole-body photograph is a pose reference.',
        'Proximal limb volumes are occluded by the torso; visible joints are rounded canine anatomy suggestions.',
        'Guide geometry is unverified art direction; generated-photo anatomy and continuity need separate inspection.']
    return data

def taper(a,b,wa,wb,tone):
    dx,dy=b[0]-a[0],b[1]-a[1]
    length=max(math.hypot(dx,dy),0.001)
    nx,ny=-dy/length,dx/length
    pts=[(a[0]+nx*wa/2,a[1]+ny*wa/2), (b[0]+nx*wb/2,b[1]+ny*wb/2),
         (b[0]-nx*wb/2,b[1]-ny*wb/2),(a[0]-nx*wa/2,a[1]-ny*wa/2)]
    f=lambda q:f'{q[0]:.2f},{q[1]:.2f}'
    return f'<path d="M {f(pts[0])} L {f(pts[1])} Q {f(b)} {f(pts[2])} L {f(pts[3])} Q {f(a)} {f(pts[0])} Z" fill="{tone}"/>'

def leg_volume(data,name,far):
    points=list(data['legs'][name]['joints'].values())
    tone='#879096' if far else '#394248'
    widths=[108,53,30] if 'fore' in name else [142,80,34,31]
    parts=[]
    for i in range(len(points)-1):
        parts.append(taper(points[i],points[i+1],widths[i],widths[i+1],tone))
    for i,p in enumerate(points[1:-1],1):
        parts.append(f'<circle cx="{p[0]:.2f}" cy="{p[1]:.2f}" r="{widths[i]/2:.2f}" fill="{tone}"/>')
    p=points[-1]
    parts.append(f'<path d="M {p[0]-25:.2f},{p[1]-13:.2f} Q {p[0]-38:.2f},{p[1]+2:.2f} {p[0]-13:.2f},{p[1]+1:.2f} L {p[0]+16:.2f},{p[1]-1:.2f} Q {p[0]+20:.2f},{p[1]-19:.2f} {p[0]+2:.2f},{p[1]-21:.2f} Z" fill="{tone}"/>')
    return parts

def make_svg(data):
    # Reuse authored torso/head outlines without altering any v2 files.
    # Its frame field is only the phase parameter during outline rendering.
    outline_data=copy.deepcopy(data)
    outline_data['frame']=data['control_phase_t']+1
    original=ET.fromstring(v2.make_svg(outline_data))
    tags=lambda e:e.tag.rsplit('}',1)[-1]
    selected=[]
    for e in original:
        if e.attrib.get('fill') in ('#495057','#d9dfe1','#18212a'):
            selected.append(e)
    parts=[f'<svg xmlns="http://www.w3.org/2000/svg" width="{WIDTH}" height="{HEIGHT}" viewBox="0 0 {WIDTH} {HEIGHT}">',
           '<rect width="1536" height="1024" fill="#e9e9e9"/>',
           f'<path d="M110 {FLOOR} H1460" stroke="#bbbbbb" stroke-width="2"/>']
    for name in ['far_fore','far_hind','near_hind','near_fore']:
        parts.extend(leg_volume(data,name,name.startswith('far')))
    tail=data['body_points']['tail']
    f=lambda p:f'{p[0]:.2f},{p[1]:.2f}'
    parts.append(f'<path d="M {f(tail[0])} C {f(tail[1])} {f(tail[2])} {f(tail[3])}" stroke="#495057" stroke-width="42" stroke-linecap="round" fill="none"/>')
    # Torso/head covers the proximal limbs instead of exposing skeletal roots.
    for e in selected:
        e.tag=tags(e)
        parts.append(ET.tostring(e,encoding='unicode'))
    parts.append('</svg>')
    return '\n'.join(parts)+'\n'

def main():
    p=argparse.ArgumentParser()
    p.add_argument('--output',type=Path,default=Path('asset-staging/border-collie-run-imagegen-v3-20261006/guides'))
    args=p.parse_args();args.output.mkdir(parents=True,exist_ok=True)
    frames=[frame_data(i) for i in range(1,COUNT+1)]
    errors=[]
    for f in frames:
        stem=f"Guide_{f['frame']:03d}"
        (args.output/f'{stem}.svg').write_text(make_svg(f))
        (args.output/f'{stem}.json').write_text(json.dumps(f,ensure_ascii=False,indent=2)+'\n')
        for name,leg in f['legs'].items():
            if leg['unreachable_extension_px'] or leg['unreachable_fold_px']:
                errors.append({'frame':f['frame'],'leg':name,'extension':leg['unreachable_extension_px'],'fold':leg['unreachable_fold_px']})
    (args.output/'trajectory.json').write_text(json.dumps({'schema':'v3-sixteen-equal-time-gallop-pose-controls','frame_count':COUNT,
        'period_seconds':0.7,'phase_origin_t':17,'source_phase_period':42,'frame_duration_seconds':0.7/COUNT,
        'contact_order':['near_hind','far_hind','extended suspension','far_fore','near_fore','collected suspension'],
        'controls_are_measured_mocap':False,'frames':frames},ensure_ascii=False,indent=2)+'\n')
    check={'svg_count':COUNT,'joint_reach_errors':errors,'actual_generated_photos_verified':False,
           'note':'Numerical guide checks only; anatomy/silhouette and each generated photo require visual review.'}
    (args.output/'guide_validation.json').write_text(json.dumps(check,indent=2)+'\n')
    print(json.dumps(check))

if __name__=='__main__':main()
