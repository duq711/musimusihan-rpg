#!/usr/bin/env python3
"""Write single-frame SVG pose guides and periodic joint trajectories.

These are deterministic drawing references, not final dog art or a 3D rig.
The script writes SVG/JSON text only; it never creates or edits raster pixels.
"""

from __future__ import annotations

import argparse
import json
import math
from pathlib import Path

COUNT = 42
WIDTH, HEIGHT = 1536, 1024
FLOOR = 850.0
PERIOD = float(COUNT)


def curve(t, keys, forced=None):
    """Periodic, shape-preserving cubic Hermite interpolation.

    Explicit support-edge velocities make landing and lift-off join the
    linear ground path without a horizontal speed jump or vertical pop.
    """
    forced = forced or {}
    t %= PERIOD
    for i in range(len(keys) - 1):
        a, b = keys[i], keys[i + 1]
        if a[0] <= t <= b[0]:
            break
    def slope(k):
        x, y = keys[k]
        if x in forced:
            return forced[x]
        if k in (0, len(keys) - 1):
            prev = (keys[-2][0] - PERIOD, keys[-2][1])
            nxt = keys[1]
        else:
            prev, nxt = keys[k - 1], keys[k + 1]
        dl = (y - prev[1]) / (x - prev[0])
        dr = (nxt[1] - y) / (nxt[0] - x)
        # Monotonicity limits reduce artificial foot reversals/overshoot.
        if dl * dr <= 0:
            return 0.0
        return 2 * dl * dr / (dl + dr)
    u = (t - a[0]) / (b[0] - a[0])
    span = b[0] - a[0]
    return ((2*u**3 - 3*u**2 + 1) * a[1]
            + (u**3 - 2*u**2 + u) * span * slope(i)
            + (-2*u**3 + 3*u**2) * b[1]
            + (u**3 - u**2) * span * slope(i + 1))


PAWS = {
    'near_hind': {
        'contact': (5.0, 11.0),
        'x': [(0,920),(5,980),(11,1190),(17,1295),(23,1100),(32,940),(36,900),(42,920)],
        'y': [(0,770),(5,850),(11,850),(17,720),(23,720),(32,780),(36,765),(42,770)],
        'hock_angle': [(0,-42),(5,-67),(11,-67),(17,-90),(23,-110),(32,-42),(42,-42)],
    },
    'far_hind': {
        'contact': (7.0, 13.0),
        'x': [(0,890),(7,965),(13,1175),(17,1290),(23,1140),(32,960),(36,915),(42,890)],
        'y': [(0,750),(7,850),(13,850),(17,755),(23,700),(32,750),(36,735),(42,750)],
        'hock_angle': [(0,-42),(7,-67),(13,-67),(17,-90),(23,-110),(32,-42),(42,-42)],
    },
    'far_fore': {
        'contact': (22.0, 29.0),
        'x': [(0,590),(7,480),(13,370),(17,340),(22,410),(29,655),(34,630),(38,610),(42,590)],
        'y': [(0,725),(7,730),(13,700),(17,735),(22,850),(29,850),(34,755),(38,725),(42,725)],
    },
    'near_fore': {
        'contact': (24.0, 32.0),
        'x': [(0,550),(7,450),(13,350),(17,300),(24,380),(32,660),(36,620),(39,575),(42,550)],
        'y': [(0,740),(7,715),(13,680),(17,710),(24,850),(32,850),(36,765),(39,740),(42,740)],
    },
}

BODY_Y = [(0,0),(5,14),(8,30),(11,14),(13,0),(17,-38),
          (22,-4),(25,30),(29,20),(32,-5),(36,-28),(42,0)]
BODY_PITCH = [(0,2),(5,3),(8,5),(13,2),(17,0),(22,-3),
              (25,-6),(29,-3),(32,1),(36,3),(42,2)]
SPINE_FLEX = [(0,20),(8,5),(17,-8),(25,4),(32,20),(36,27),(42,20)]
HEAD_NOD = [(0,0.5),(8,-0.5),(17,0.25),(22,-0.75),(25,1),(29,-0.5),(36,0.75),(42,0.5)]


def transform(p, dy, angle, origin=(820.0,580.0)):
    x, y = p[0] - origin[0], p[1] - origin[1]
    c, s = math.cos(angle), math.sin(angle)
    return (origin[0] + x*c - y*s, origin[1] + dy + x*s + y*c)


def two_link(root, end, upper, lower, bend):
    """Solve planar fixed-length links, returning diagnostic reach error."""
    dx, dy = end[0]-root[0], end[1]-root[1]
    actual = math.hypot(dx, dy)
    d = min(max(actual, abs(upper-lower)+0.001), upper+lower-0.001)
    ux, uy = dx / max(actual, 0.001), dy / max(actual, 0.001)
    a = (upper*upper - lower*lower + d*d) / (2*d)
    h = math.sqrt(max(0, upper*upper - a*a))
    if bend == 'caudal_elbow':
        px, py = uy, -ux
    else:  # Canine stifle folds toward the head (cranial side).
        px, py = -uy, ux
    joint = (root[0] + ux*a + px*h, root[1] + uy*a + py*h)
    return joint, max(0.0, actual-(upper+lower)), max(0.0, abs(upper-lower)-actual)


def phase_label(t):
    if t < 5 or t >= 32:
        return 'gathered aerial'
    if t < 13:
        return 'hind landing, compression and launch'
    if t < 22:
        return 'extended aerial'
    return 'fore landing, compression and release'


def compensated_head_transform(t, dy, pitch):
    """Neck compensation keeps the gaze level while the trunk pitches.

    The muzzle follows a small fraction of the chest bounce. A separate neck
    connector in the SVG maintains its physical attachment to the shoulder.
    """
    neck=(420.0,515.0)
    pivot=transform(neck,dy,pitch)
    lift=-0.75*(pivot[1]-neck[1])
    angle=-pitch+math.radians(curve(t,HEAD_NOD))
    def hf(p):
        q=transform(transform(p,0,angle,neck),dy,pitch)
        return (q[0],q[1]+lift)
    return hf, angle, lift


def frame_data(t):
    dy = curve(t, BODY_Y)
    pitch_deg = curve(t, BODY_PITCH)
    pitch = math.radians(pitch_deg)
    tf = lambda p: transform(p, dy, pitch)
    roots = {'near_fore':tf((600,590)), 'far_fore':tf((616,580)),
             'near_hind':tf((1020,610)), 'far_hind':tf((1036,600))}
    legs = {}
    for name, spec in PAWS.items():
        start, finish = spec['contact']
        vx = 35.0
        paw = (curve(t, spec['x'], {start:vx, finish:vx}),
               curve(t, spec['y'], {start:0.0, finish:0.0}))
        root = roots[name]
        contact = start <= t < finish
        if 'fore' in name:
            elbow, over, under = two_link(root,paw,185,190,'caudal_elbow')
            joints = {'shoulder':root,'elbow':elbow,'paw':paw}
            lengths = [185,190]
        else:
            theta = math.radians(curve(t,spec['hock_angle']))
            hock = (paw[0]+90*math.cos(theta), paw[1]+90*math.sin(theta))
            knee, over, under = two_link(root,hock,155,135,'cranial_stifle')
            joints = {'hip':root,'stifle':knee,'hock':hock,'paw':paw}
            lengths = [155,135,90]
        legs[name] = {'contact':contact,'support_start_frame':start+1,
                      'support_last_frame':finish,
                      'joints':{k:[round(v[0],4),round(v[1],4)] for k,v in joints.items()},
                      'segment_lengths_px':lengths,
                      'unreachable_extension_px':round(over,4),
                      'unreachable_fold_px':round(under,4)}
    # Tail waves travel down its length and react to trunk acceleration.
    phase = 2*math.pi*t/PERIOD
    tail = [tf((1110,550)), tf((1190,555+10*math.sin(phase-0.3))),
            tf((1280,575+18*math.sin(phase-0.65))),
            tf((1375,590+26*math.sin(phase-1.0)))]
    head_tf, head_angle, neck_lift = compensated_head_transform(t,dy,pitch)
    return {'frame':int(t)+1,'time_seconds':round(t/60,6),
            'cycle_phase':round(t/PERIOD,8),'stage':phase_label(t),
            'body_vertical_offset_px':round(dy,4),
            'body_pitch_degrees':round(pitch_deg,4),
            'spine_flex_px':round(curve(t,SPINE_FLEX),4),
            'head_nod_degrees':round(math.degrees(head_angle),4),
            'world_head_gaze_degrees':round(curve(t,HEAD_NOD),4),
            'neck_compensation_y_px':round(neck_lift,4),
            'body_points':{'shoulder':[round(v,4) for v in tf((600,590))],
                           'hip':[round(v,4) for v in tf((1020,610))],
                           'nose':[round(v,4) for v in head_tf((184,528))],
                           'tail':[[round(v,4) for v in p] for p in tail]},
            'legs':legs}


def fmt(p):
    return f'{p[0]:.2f},{p[1]:.2f}'


def make_svg(data):
    t = data['frame']-1
    dy = data['body_vertical_offset_px']
    pitch = math.radians(data['body_pitch_degrees'])
    flex = data['spine_flex_px']
    tf = lambda p: transform(p,dy,pitch)
    hf, head_angle, neck_lift = compensated_head_transform(t,dy,pitch)
    def path(points):
        return ' '.join(f'{cmd} '+ ' '.join(fmt(tf(p)) for p in pts)
                        for cmd,pts in points)
    torso = path([
        ('M',[(485,546)]),('C',[(550,491),(615,476),(684,480)]),
        ('C',[(800,481-flex),(932,482-flex/2),(1027,492)]),
        ('C',[(1118,500),(1152,559),(1110,626)]),
        ('C',[(1052,673),(1017,655),(945,645)]),
        ('C',[(872,666+flex*.2),(756,656),(680,640)]),
        ('C',[(594,665),(542,621),(485,546)]),('Z',[])])
    # A side-profile collie head/ruff shape. This is a generic guide only.
    head = ' '.join(f'{cmd} '+ ' '.join(fmt(hf(p)) for p in pts) for cmd,pts in [
        ('M',[(485,546)]),('C',[(465,520),(451,492),(434,462)]),
        ('C',[(410,437),(379,444),(352,465)]),
        ('L',[(342,423),(325,411),(331,474)]),
        ('C',[(298,486),(266,496),(240,515)]),
        ('L',[(184,528)]),('C',[(173,537),(197,557),(231,560)]),
        ('L',[(273,580)]),('C',[(310,592),(336,587),(371,575)]),
        ('C',[(406,598),(442,606),(466,629)]),
        ('C',[(462,595),(472,568),(485,546)]),('Z',[])])
    parts = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{WIDTH}" height="{HEIGHT}" viewBox="0 0 {WIDTH} {HEIGHT}">',
             '<rect width="1536" height="1024" fill="#e9e9e9"/>',
             f'<path d="M 110 {FLOOR} H 1460" stroke="#bababa" stroke-width="2"/>']
    def draw_leg(name,far):
        leg = data['legs'][name]
        points = list(leg['joints'].values())
        tone = '#8a939a' if far else '#313a42'
        stroke = 29 if 'fore' in name else 33
        parts.append(f'<polyline points="{" ".join(fmt(p) for p in points)}" fill="none" stroke="{tone}" stroke-width="{stroke}" stroke-linecap="round" stroke-linejoin="round"/>')
        # Distinct small joint centers expose the intended bends without text.
        for p in points[1:-1]:
            parts.append(f'<circle cx="{p[0]:.2f}" cy="{p[1]:.2f}" r="{stroke/2+2}" fill="{tone}"/>')
        paw = points[-1]
        parts.append(f'<path d="M {paw[0]-21:.2f},{paw[1]-8:.2f} Q {paw[0]-29:.2f},{paw[1]+3:.2f} {paw[0]-5:.2f},{paw[1]+1:.2f} L {paw[0]+14:.2f},{paw[1]-1:.2f} Q {paw[0]+14:.2f},{paw[1]-12:.2f} {paw[0]+2:.2f},{paw[1]-16:.2f} Z" fill="{tone}"/>')
    # The far legs belong behind the trunk; near legs remain visible in front.
    draw_leg('far_fore',True)
    draw_leg('far_hind',True)
    tail = data['body_points']['tail']
    parts.append(f'<path d="M {fmt(tail[0])} C {fmt(tail[1])} {fmt(tail[2])} {fmt(tail[3])}" stroke="#444b50" stroke-width="35" stroke-linecap="round" fill="none"/>')
    parts.append(f'<path d="{torso}" fill="#495057"/>')
    neck_bridge=' '.join(fmt(p) for p in [tf((530,505)),hf((445,488)),hf((458,590)),tf((550,628))])
    parts.append(f'<polygon points="{neck_bridge}" fill="#495057"/>')
    parts.append(f'<path d="{head}" fill="#495057"/>')
    draw_leg('near_hind',False)
    draw_leg('near_fore',False)
    eye = hf((310,506))
    parts.append(f'<circle cx="{eye[0]:.2f}" cy="{eye[1]:.2f}" r="5" fill="#18212a"/>')
    # Guide head and ruff get minimal contrast to aid consistent face placement.
    stripe = ' '.join(fmt(hf(p)) for p in [(300,491),(268,521),(236,548),(275,558),(327,525)])
    parts.append(f'<polygon points="{stripe}" fill="#d9dfe1"/>')
    parts.append('</svg>')
    return '\n'.join(parts)+'\n'


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--output',type=Path,default=Path('asset-staging/border-collie-run-imagegen-v2-20261006/guides'))
    args=parser.parse_args()
    args.output.mkdir(parents=True,exist_ok=True)
    frames=[frame_data(t) for t in range(COUNT)]
    for f in frames:
        stem=f"Guide_{f['frame']:03d}"
        (args.output/f'{stem}.svg').write_text(make_svg(f),encoding='utf-8')
        (args.output/f'{stem}.json').write_text(json.dumps(f,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    # Numerical validation checks the trajectories rather than mirroring SVG.
    closure=frame_data(0)
    end=frame_data(PERIOD)
    closure_fields=['body_vertical_offset_px','body_pitch_degrees','spine_flex_px',
                    'head_nod_degrees','body_points','legs']
    exact_closure=all(closure[k]==end[k] for k in closure_fields)
    errors=[]
    max_step=0
    for t in range(COUNT):
        a,b=frames[t],frames[(t+1)%COUNT]
        for name in PAWS:
            leg=a['legs'][name]
            if leg['unreachable_extension_px']>0 or leg['unreachable_fold_px']>0:
                errors.append({'frame':t+1,'leg':name,'extension_px':leg['unreachable_extension_px'],'fold_px':leg['unreachable_fold_px']})
            p,q=leg['joints']['paw'],b['legs'][name]['joints']['paw']
            max_step=max(max_step,math.dist(p,q))
            if leg['contact'] and abs(p[1]-FLOOR)>0.001:
                errors.append({'frame':t+1,'leg':name,'invalid_contact_y':p[1]})
    envelope={
        'schema':'border_collie_run_v2_guides/1','frame_count':COUNT,
        'canvas':[WIDTH,HEIGHT],'floor_y':FLOOR,
        'nominal_fps':60,'nominal_cycle_seconds':0.7,
        'facing':'left','near_limbs':'left','far_limbs':'right',
        'contact_order':['near_hind','far_hind','far_fore','near_fore'],
        'guide_intent':'Deterministic side-view 2D anatomy, foot trajectories, torso motion and contact references for individually generated art.',
        'limitations':['A qualitative constructed gallop, not measured motion capture or a physically simulated 3D model.',
                       'Generated final images must be checked against these guides; a guide alone does not validate final anatomy or continuity.'],
        'continuous_checks':{'periodic_closure_exact':exact_closure,
                             'maximum_one_frame_paw_step_px':round(max_step,4),
                             'unreachable_or_invalid_contact_errors':errors},
        'frames':frames}
    (args.output/'trajectory.json').write_text(json.dumps(envelope,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({'output':str(args.output),'svg_count':COUNT,'check_errors':errors,'max_paw_step_px':round(max_step,3)},ensure_ascii=False))
    if errors:
        raise SystemExit(1)


if __name__=='__main__':
    main()
