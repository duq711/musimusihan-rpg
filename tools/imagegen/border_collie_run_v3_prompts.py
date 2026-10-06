#!/usr/bin/env python3
"""Plan independent pose-first imagegen calls; never creates or edits final pixels."""
import argparse, json
from pathlib import Path

DEFAULT = Path(__file__).resolve().parents[2] / 'asset-staging/border-collie-run-imagegen-v3-20261006'
POSES = [
 ('최대 확장 공중 자세', 'Maximum extended flight: both forelegs reach left, both hind legs trail right, long unfolded torso, four paws airborne.'),
 ('앞발 하강 · 뒷다리 회수 시작', 'Descending extended flight: forepaws swing downward toward landing, hind stifles begin to fold forward; forelegs and hind legs differ visibly from maximum extension.'),
 ('첫 앞발 착지', 'The far forepaw is the first forepaw to reach the ground; near forepaw is still descending and ahead, hind paws remain airborne; chest starts taking weight.'),
 ('두 앞발 지지 · 가슴 눌림', 'Both forepaws support the body on the ground; chest is visibly lower with bent elbows absorbing impact, hips higher, hind legs folded and airborne under the belly.'),
 ('앞다리 위로 몸통 이동', 'Fore support after landing: torso passes forward over the planted forepaws, forelegs sweep rearward relative to the trunk, hind legs swing forward underneath; chest begins to rise.'),
 ('앞발 하나 회수 · 마지막 앞발 지지', 'One forepaw has lifted and folds toward the chest while the other remains in its last support behind the shoulder; hind legs swing far forward under the belly.'),
 ('앞발 이륙 · 네 다리 모으기', 'Both forepaws leave the ground; all four limbs actively fold underneath the dog; the back begins rounding, forepaws recover behind the chest and hind paws reach forward.'),
 ('모은 공중 자세', 'Gathered aerial phase: spine visibly rounded, forelegs folded back and hind stifles tucked forward underneath the belly, four separated paws airborne.'),
 ('뒷발을 앞으로 가져오기', 'After gathered flight, hind paws now advance forward and start descending beneath the hips; forepaws have begun swinging forward out of their fold. This must be a new silhouette, not the same gathered pose.'),
 ('뒷발 내려오기 · 앞다리 열림', 'Hind limbs unfold downward toward the coming hind landing, first hindpaw clearly lower than the other; forelegs unfold farther forward, shoulders/head lowered modestly.'),
 ('첫 뒷발 착지 준비', 'First hindpaw reaches down close to ground beneath the body, the other hindpaw remains higher and staggered. Forelegs continue opening forward and stay airborne.'),
 ('뒷발 하강 마지막 단계', 'First hindpaw is now immediately above the ground and the pelvis descends with it; second hindpaw is still in the air. Forelegs reach farther forward with clearly opened elbows.'),
 ('첫 뒷발 지지', 'First hindpaw supports the dog, second hindpaw is finishing its descent; hip and hind stifle bend to accept weight, forelegs reach forward in the air.'),
 ('두 뒷발 지지 · 골반 눌림', 'Both hind paws are grounded and staggered, pelvis drops and stifles load for propulsion; forelegs extend forward airborne, chest starts rising. The lower hip must make the body visibly different from first contact.'),
 ('뒷다리 추진 · 한 발 이륙', 'Hind propulsion: pelvis rises, one hindpaw already airborne trailing back and the last supporting hindpaw pushes behind the hip. Forelegs reach forward and the spine unfolds.'),
 ('뒷발 이륙 · 전신 펼치기', 'Last hindpaw has left the ground; all four paws airborne, hind legs extend back and forelegs continue reaching left toward the next maximum-extension frame. Torso unfolds into a long airborne stride.'),
]

def catalog(base):
    common = ('Create ONE single standalone frame of the SAME realistic black and white athletic Border Collie galloping LEFT. Landscape 1536x1024, strict orthographic side profile, full dog with all paws, ears and tail within frame. '
      'REFERENCE 1 is the full-body POSE guide and determines this frame: reproduce its whole-body silhouette, body pitch/height, four limb placements and paw contact state. Make a fresh full-body pose, not a retouch of another dog photo. '
      'REFERENCE 2 is ONLY a cropped appearance portrait with no legs: use the same face, brown eye, white blaze/muzzle/ruff, black back, white paws and white tail tip. Do not use the portrait scale; full-body framing comes from reference 1. '
      'Anatomically credible canine shoulder/elbow and hip/stifle/hock joints, four connected limbs only, near and far paws readable, no extra legs. Realistic detailed medium fur with a clean silhouette. '
      'Uniform pale light-gray background, soft even lighting, no textured floor, no visible horizon line, no motion blur, no labels, no grid, no collage, no cropping or automatic zoom to fill the frame. '
      'Virtual contact plane is around y=850; only the supporting paws touch it, all other paws are visibly raised. Leg articulation and body compression must change together. ')
    frames=[]
    for n,(label,pose) in enumerate(POSES,1):
        g=base/'guides'/f'Guide_{n:03d}.json'
        guide=json.loads(g.read_text())
        frames.append({'frame':n,'filename':f'Frame_{n:03d}.png','label_ko':label,'caption_ko':'',
          'pose_description_en':pose,'guide':f'guides/Guide_{n:03d}.json',
          'reference_roles':['full-body pose guide FIRST','cropped appearance portrait SECOND; no limb pose'],
          'referenced_image_paths':[str(g.with_suffix('.png')),str(base/'references/dog-appearance-portrait.png')],
          'prompt':common+' THIS FRAME: '+pose,
          'planned_cycle_phase':guide.get('cycle_phase')})
    return {'schema':'border-collie-run-imagegen-v3-pose-first','frame_count':16,
      'generator':'built-in imagegen; one independent image per call',
      'shared_constraints':{'canvas':[1536,1024],'direction':'left','background':'uniform pale gray',
        'no_raster_editing':True,'separate_frames':True,'appearance_reference_has_no_legs':True},
      'reference_notes':'Guide phases are art controls, not measured motion. Actual generation receipts are authoritative; frame001 was made before the portrait using the prior extended guide and a prior full-body identity reference.',
      'frames':frames}

def main():
    p=argparse.ArgumentParser();p.add_argument('--root',type=Path,default=DEFAULT);p.add_argument('--frame',type=int);a=p.parse_args();b=a.root.resolve();c=catalog(b)
    if a.frame:
        print(json.dumps(c['frames'][a.frame-1],ensure_ascii=False,indent=2));return
    (b/'prompts.json').write_text(json.dumps(c,ensure_ascii=False,indent=2)+'\n');print(json.dumps({'frames':16,'catalog':str(b/'prompts.json')}))

if __name__=='__main__':main()
