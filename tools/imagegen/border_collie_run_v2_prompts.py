#!/usr/bin/env python3
"""Author text prompts from fixed pose controls; never process final image pixels."""
import argparse
import json
from pathlib import Path

SHARED = '''Use case: sketch-to-render. ONE separate photoreal full-body running Border Collie image, not a multi-pose sheet. Input1 is the dominant pose/layout edit target: render its four-limb silhouette as real canine anatomy, at that pose, position and scale. Input2 is the new v2 Frame001 dog, used ONLY for exact face, coat, identity, camera, lighting and studio appearance. Any additional photographs are neighboring pose references, not extra dogs. Produce exactly1536x1024, fixed left-facing strict side view. Whole nose, four paws and tail visible. Same black-white long-haired athletic adult, white blaze/muzzle/chest/paws and tail tip, semi-prick ears, brown eye. Matte light-gray studio, same floor y850 and soft contact shadow. Keep torso center around x800, same body proportions. Guide shapes become realistic rounded flesh and fur, with no visible guide lines. Four connected canine limbs, separate paws, normal shoulder/elbow/wrist and hip/stifle/hock; never fused, missing or twisted limbs. Near means left side visible to camera, far means right side. Changes in body height, spine flex and pitch must carry the whole skeleton. Head gaze remains nearly level through small neck compensation. Ears, coat and tail respond mildly to motion. Clean sharp realistic action photo, no motion blur, no text or accessories. The pose should progress only one small instant from a neighboring image, while fulfilling this guide's paw contacts and targets. Target coordinates are control suggestions; use natural limb articulation rather than square sketch edges.'''

def make_prompt(g):
    body=g['body_points']; n=g['frame']; lines=[SHARED,f"FRAME {n:03d} of42. Phase: {g['stage']}. Shoulder target{body['shoulder']}; hip{body['hip']}; nose{body['nose']}. Body vertical offset{g['body_vertical_offset_px']}px; pitch{g['body_pitch_degrees']}degrees; spine flex{g['spine_flex_px']}px."]
    for name,leg in g['legs'].items():
        joint=leg['joints']; state='PLANTED at floor y850; weight-bearing' if leg['contact'] else 'AIRBORNE, visibly above floor'
        lines.append(f"{name}: {state}. Joint path {joint}.")
    if 6<=n<=13:
        lines.append('Hind support/propulsion: rump lowers initially as stifles and hocks soften, then opens to push; chest is lifted relative to pelvis. Forelegs are recovering and begin reaching. Paws planted on the moving floor pass backward/right relative to body. No whole-body rigid slide.')
    elif 14<=n<=22:
        lines.append('Rear push transitions into extended aerial flight. Hindlegs open backward, frontlegs reach forward and then descend toward their sequential landings. All four paws are airborne; lumbar spine unfolds; avoid sudden paw jumps or teleporting the head.')
    elif 23<=n<=32:
        lines.append('Foreleg landing/support: touch the floor sequentially, then chest lowers as shoulder/elbow/wrist absorb weight. Knees/hocks behind the pelvis fold for recovery; hindlegs do not become two straight sticks. Planted forepaws pass backward/right as body travels left. Keep contact floor coherent.')
    else:
        lines.append('Gathered flight/recovery: forelegs fold naturally below the chest, hind stifles come forward and hocks fold under the belly. Mild flexed spine and higher trunk; all paws off the floor. Body and head respond gently rather than staying frozen. Last frames must close smoothly toFrame001.')
    return '\n'.join(lines)

def main():
    p=argparse.ArgumentParser(); p.add_argument('base',type=Path); p.add_argument('--frame',type=int); a=p.parse_args()
    frames=[]
    for n in range(1,43):
        guide=f'guides/Guide_{n:03d}.json'; g=json.loads((a.base/guide).read_text())
        frames.append({'frame':n,'filename':f'Frame_{n:03d}.png','guide':guide,'stage':g['stage'],'intended_ground_contacts':[k for k,v in g['legs'].items() if v['contact']],'prompt':make_prompt(g),'reference_roles':['first: pose guide','second: new v2 identity','optional: adjacent accepted pose']})
    catalog={'schema':'border-collie-run-v2-controlled-prompts','mode':'built-in image_gen, one separate selected image per call','shared_constraints':SHARED,'frame_count':42,'frames':frames,'reference_notes':'42 phase slots are an art schedule, not measured motion capture. Qualitative contact order, compression and recovery are informed by uploader-owned Brixiv side-view slow-motion and primary gait research. Final image adherence is approximate and requires adjacent-frame visual review.','reference_urls':['https://www.pexels.com/video/side-view-of-dog-running-in-slow-motion-9898378/','https://journals.biologists.com/jeb/article/210/2/208/17106/Ground-forces-applied-by-galloping-dogs','https://vanat.ahc.umn.edu/gaits/rotGallop.html']}
    if a.frame:
        print(json.dumps(frames[a.frame-1],ensure_ascii=False)); return
    (a.base/'prompts.json').write_text(json.dumps(catalog,ensure_ascii=False,indent=2)+'\n');print('Wrote42 controlled text prompts; generated images0')

if __name__=='__main__':main()
