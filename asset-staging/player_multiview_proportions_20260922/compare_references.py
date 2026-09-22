#!/usr/bin/env python3
"""Measure actual calibrated renders against supplied photographs; never edit assets.

Run with a Python providing Pillow and numpy. Default paths are repository-relative.
This creates comparison_report.json and compare.html and copies the four original
reference inputs unchanged into reference_images on the first run. It deliberately
does not emit a global anatomy score or claim exact photograph/mesh equivalence.
"""
from pathlib import Path
import argparse
import hashlib
import html
import json
import shutil
import numpy as np
from PIL import Image

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
INPUT_BASE = Path('/var/folders/7r/486gfldn6f57tqk3gxh1rmfh0000gn/T')
INPUTS = {
    'front': 'e8980fc4-063c-4d63-a616-496c03b5c21c',
    'back': 'a04aec78-ce3b-4418-9570-901596d7d664',
    'right': 'bacf3c9b-c21a-475b-8cb7-e205083a37bd',
    'left': 'fbe38c47-b57f-4312-b4a5-ac4adc5b6582',
}
LABELS = {'front': '정면', 'back': '후면', 'right': '오른쪽을 보는 측면', 'left': '왼쪽을 보는 측면'}
GROUPS = {
    'shoulder_envelope': '어깨 전체 폭', 'core_torso': '몸통 중심 폭',
    'arm_left': '화면 왼쪽 팔 폭', 'arm_right': '화면 오른쪽 팔 폭',
    'leg_left': '화면 왼쪽 다리 폭', 'leg_right': '화면 오른쪽 다리 폭',
    'crotch_gap': '가랑이 중앙 간격', 'side_depth_proxy': '측면 상체 깊이(팔 겹침 포함)',
}
SCALE_M = 1.712215677 / 1365


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def mask_for(path, reference=False):
    rgb = np.asarray(Image.open(path).convert('RGB')).astype(float)
    if reference:
        mask = (rgb.min(2) < 165) | ((rgb[:, :, 0]-rgb[:, :, 2] > 14) & (rgb.mean(2) < 225))
    else:
        # Actual clay passes have an opaque dark environment. Do not threshold
        # the textured black clothing; material darkness is not silhouette.
        mask = rgb.mean(2) > 80
    return mask


def runs_at(mask, y):
    line = mask[max(0, y-1):y+2].any(0)
    edge = np.diff(np.r_[False, line, False].astype(int))
    return [[int(a), int(b-1)] for a, b in zip(np.where(edge == 1)[0], np.where(edge == -1)[0]) if b-a >= 4]


def select_run(runs, category):
    if category in ('shoulder_envelope', 'side_depth_proxy'):
        return [runs[0][0], runs[-1][1]] if runs else None
    if category == 'core_torso':
        return next((r for r in runs if r[0] <= 533.5 <= r[1]), None)
    if category.startswith('arm_'):
        candidates = [r for r in runs if (r[1] < 395 if category.endswith('left') else r[0] > 670)]
    else:
        candidates = [r for r in runs if (280 < (r[0]+r[1])/2 < 533.5 if category.endswith('left') else 533.5 < (r[0]+r[1])/2 < 800)]
    return max(candidates, key=lambda r:r[1]-r[0], default=None)


def center_gap(mask, y):
    line = mask[max(0,y-1):y+2].any(0)
    center = 533
    if line[center]:
        return [center, center]
    left = np.where(line[340:center])[0]
    right = np.where(line[center:725])[0]
    if not len(left) or not len(right):
        return None
    return [int(left[-1]+340), int(right[0]+center)]


def metric(ref, model, category, y):
    rr, mr = runs_at(ref,y), runs_at(model,y)
    a = center_gap(ref,y) if category == 'crotch_gap' else select_run(rr,category)
    b = center_gap(model,y) if category == 'crotch_gap' else select_run(mr,category)
    if a is None or b is None:
        return {'category':category,'pixel_y':y,'measurable':False,'reason':'Required separated foreground run was not visible in both images.'}
    wa, wb = a[1]-a[0], b[1]-b[0]
    return {
        'category':category,'pixel_y':y,'measurable':True,
        'reference_span_px':a,'model_span_px':b,'reference_width_px':wa,'model_width_px':wb,
        'delta_width_px':wb-wa,'delta_width_percent':round(100*(wb-wa)/wa,2) if wa else None,
        'delta_center_px':round((sum(b)-sum(a))/2,2),
        'reference_width_over_common_anatomical_height':round(wa/1365,6),
        'model_width_over_common_anatomical_height':round(wb/1365,6),
        'equivalent_delta_m_at_front_calibration':round((wb-wa)*SCALE_M,6),
        'reference_runs_px':rr,'model_runs_px':mr,
        'uncertainty_note':'Approximate silhouette edge ±3px per side; garment/pose differences are not measurement error.',
    }


def outline(mask):
    # Row-edge guides are a vector visualization of the measured segmentation.
    # Exclude the face/hair deliberately. Original PNG files remain unchanged.
    pieces=[]
    for y in range(230, min(1410,mask.shape[0]),2):
        for a,b in runs_at(mask,y):
            pieces.extend((f'M{a},{y}v2',f'M{b},{y}v2'))
    return ''.join(pieces)


def anchored_side_profile(reference, model, view):
    """Compare leg position relative to the visible upper-thigh envelope."""
    rows=[]
    for y in (800,820,840,1000,1060,1100,1180,1220,1260):
        a=max(runs_at(reference,y),key=lambda p:p[1]-p[0])
        b=max(runs_at(model,y),key=lambda p:p[1]-p[0])
        rows.append({'pixel_y':y,'reference_span':a,'model_span':b,'raw_center_delta_px':(sum(b)-sum(a))/2})
    anchor=float(np.median([r['raw_center_delta_px'] for r in rows if r['pixel_y']<=840]))
    direction=1 if view=='right' else -1
    for row in rows:
        row['pelvis_anchored_forward_residual_px']=round(direction*(row['raw_center_delta_px']-anchor),3)
        row['equivalent_residual_m']=round(row['pelvis_anchored_forward_residual_px']*SCALE_M,6)
    return {'pelvis_anchor_rows':[800,820,840],'anchor_center_offset_px':anchor,'rows':rows}


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--render-dir',type=Path,default=ROOT/'godot-game/artifacts/visual_qa/player_appearance/multiview_proportions_20260922')
    parser.add_argument('--label',default='latest')
    args=parser.parse_args()
    render_dir=args.render_dir.resolve()
    reference_dir=HERE/'reference_images';reference_dir.mkdir(exist_ok=True)
    manifest=json.loads((render_dir/'capture_manifest.json').read_text())
    report={
        'schema_version':1,'label':args.label,'model_sha256':manifest['model_sha256'],
        'capture_manifest':str((render_dir/'capture_manifest.json').relative_to(ROOT)),
        'renderer':manifest.get('actual_renderer'),'display_driver':manifest.get('display_driver'),
        'pixel_frame':[1086,1448],
        'calibration':{'skull_crown_y':36,'sole_y':1401,'model_height_m':1.712215677,'model_sole_z_m':.0076724137,'metres_per_pixel':SCALE_M},
        'method':{
            'reference_mask':'min(R,G,B)<165 OR (R-B>14 AND mean(R,G,B)<225)',
            'model_mask':'mean(R,G,B)>80 on actual-rendered clay pass, never on dark textured clothing',
            'row_sampling':'union of rows y-1..y+1; foreground runs >=4px',
            'core_exclusions':'No head/hair measurements; core torso rows stop at y540 to avoid belts/pouches; limb runs excluded from core torso.',
            'side_depth':'Upper-body silhouette proxy at y310..540, above belt/pouches. Arms partly occlude the torso, so this is NOT an isolated anatomical chest depth.',
            'no_rescale':'Original supplied photos and calibrated images are used in their native 1086x1448 frame; no hidden scaling or alignment.',
        },
        'limitations':[
            'Reference skull crown y36 is estimated beneath hair; model face identity/hair are not scored.',
            'The photos are not calibrated orthographic scans; body pose, cloth and camera perspective differ.',
            'Side-photo soles are approximately 20px above the common front sole. Side depth percentages include this small framing difference.',
            'A small width delta is not proof of natural anatomy. This is comparison evidence, not an automatic pass/fail gate.',
            'Clothing may legitimately exceed bare-arm or bare-chest contours. Belt and pouch contours are deliberately excluded from core ratios.',
        ],'views':{},
    }
    for view,key in INPUTS.items():
        ref=reference_dir/f'{view}.png'
        if not ref.exists():
            source=INPUT_BASE/f'codex-clipboard-{key}.png'
            shutil.copy2(source,ref)
            assert digest(ref)==digest(source)
        textured=render_dir/f'calibrated_{view}.png'
        clay=render_dir/f'calibrated_{view}_clay.png'
        for p in (ref,textured,clay):
            if Image.open(p).size!=(1086,1448):
                raise ValueError(f'Unexpected frame; do not silently scale: {p}')
        rm,mm=mask_for(ref,True),mask_for(clay)
        requests=[]
        if view in ('front','back'):
            requests += [('shoulder_envelope',y) for y in (260,280,310,335,350)]
            requests += [('core_torso',y) for y in (420,460,480,520,540)]
            requests += [(f'arm_{side}',y) for y in (420,460,480,520,540,580,600,630,660) for side in ('left','right')]
            requests += [('crotch_gap',y) for y in (775,780,785,790,795,800,810,820,845)]
            requests += [(f'leg_{side}',y) for y in (810,860,920,970,1020,1060,1100,1160,1220,1280,1320) for side in ('left','right')]
        else:
            requests += [('side_depth_proxy',y) for y in (310,335,350,380,400,420,460,480,520,540)]
        metrics=[metric(rm,mm,group,y) for group,y in requests]
        summary={}
        for group in sorted({a for a,b in requests}):
            group_metrics=[m for m in metrics if m['category']==group and m['measurable']]
            deltas=[m['delta_width_px'] for m in group_metrics]
            summary[group]={'samples':len(deltas),'median_absolute_width_delta_px':float(np.median(np.abs(deltas))) if deltas else None,'max_absolute_width_delta_px':max(map(abs,deltas),default=None)}
        report['views'][view]={
            'label':LABELS[view],
            'reference_file':str(ref.relative_to(ROOT)),'reference_sha256':digest(ref),
            'textured_render_file':str(textured.relative_to(ROOT)),'textured_render_sha256':digest(textured),
            'clay_render_file':str(clay.relative_to(ROOT)),'clay_render_sha256':digest(clay),
            'reference_url':f'reference_images/{view}.png',
            'textured_url':'../../'+str(textured.relative_to(ROOT)),
            'clay_url':'../../'+str(clay.relative_to(ROOT)),
            'metrics':metrics,'summary':summary,
            'reference_outline_svg_path':outline(rm),'model_outline_svg_path':outline(mm),
        }
        if view in ('right','left'):
            report['views'][view]['pelvis_anchored_leg_position']=anchored_side_profile(rm,mm,view)
    (HERE/'comparison_report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
    side_review={
        'model_sha256':report['model_sha256'],
        'method':'Longest foreground run; subtract median side-image alignment at upper thighs y800/820/840; positive residual is forward. Side poses and photographed near/far-leg overlap limit exact skeletal interpretation.',
        'views':{view:report['views'][view]['pelvis_anchored_leg_position'] for view in ('right','left')},
    }
    (HERE/'side_alignment_review.json').write_text(json.dumps(side_review,indent=2)+'\n')
    template=(HERE/'compare_template.html').read_text()
    template=template.replace('__REPORT_JSON__',json.dumps(report,ensure_ascii=False).replace('</','<\\/'))
    template=template.replace('__GROUPS_JSON__',json.dumps(GROUPS,ensure_ascii=False))
    (HERE/'compare.html').write_text(template)
    print(json.dumps({'model_sha256':report['model_sha256'],'label':args.label,'views':{k:v['summary'] for k,v in report['views'].items()}},ensure_ascii=False,indent=2))


if __name__=='__main__':
    main()
