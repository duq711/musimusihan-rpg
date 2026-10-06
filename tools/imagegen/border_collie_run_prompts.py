#!/usr/bin/env python3
"""Write separate built-in imagegen briefs for one new dog's gallop cycle.

This script prepares text and metadata only. It neither generates images nor
renders, interpolates, crops, or reuses the former Labrador model. Each final
frame requires its own built-in imagegen call and visual review.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path


COUNT = 42
FPS = 60
PERIOD = COUNT / FPS
GAIT_SOURCE = {
    "title": "Ground forces applied by galloping dogs",
    "authors": "Rebecca M. Walter and David R. Carrier",
    "year": 2007,
    "url": "https://journals.biologists.com/jeb/article/210/2/208/17106/Ground-forces-applied-by-galloping-dogs",
    "doi": "10.1242/jeb.02645",
    "used_for": "Qualitative contact order and the two aerial configurations only. The 0.70 s period is an illustration schedule, not a measured gait from this study.",
}

SHARED_SPEC = """Use case: photorealistic-natural.
Asset type: ONE separate full-body running-dog animation reference image.
Primary request: a completely new photorealistic athletic black-and-white Border Collie, running naturally toward the LEFT in one specified instant of a gallop.
Scene/backdrop: matte warm-light-gray seamless studio floor and backdrop, soft natural contact shadow, no props.
Subject: one healthy adult Border Collie with realistic medium-long black-and-white coat, white facial blaze, white muzzle, broad white neck/chest, white paws, black semi-prick ears, brown eyes, black nose, a black tail with white tip, and a slender athletic canine build. If the newly generated Border Collie seed is supplied, preserve its individual facial features and exact coat markings rather than inventing a different individual.
Composition/framing: fixed strict side profile, LEFT-facing, full body including all four paws and the whole tail inside the frame, level camera at the torso, constant framing and dog scale. The near-side legs are the LEFT foreleg and LEFT hindleg; far-side legs are the RIGHT foreleg and RIGHT hindleg. Use a small natural silhouette offset so all four limbs remain identifiable, without rotating the camera.
Lighting/mood: consistent soft studio daylight, crisp real fur and anatomy, sharp fast-shutter action photograph, no motion blur.
Constraints: exactly one dog and exactly four anatomically connected legs; elbows stay below the shoulder attachment and flex naturally; hind knees and hocks articulate as a real dog; paws are small natural canine paws. Keep the same head, coat, torso proportions, camera, background, lighting and frame crop throughout. Change only the stride pose, modest natural body-height/trunk motion and corresponding fur/ear/tail response. Keep the horizontal body center fixed; allow the body to descend naturally enough for the specified planted paws to meet the same floor, and rise modestly in aerial phases. The posture represents locomotion rather than shifting the dog across the composition.
Avoid: Labrador features or reuse of the previous model, extra or missing legs, fused paws, mirrored duplicate limbs, arms bent upward into the chest, distorted joints, detached limbs, paws sunk below the floor, inflated joints, extreme spine bending, cartoon style, model turntable, 3D-render appearance, hand, collar, harness, text, numbers, labels, grids, contact sheets, multiple panels or montage. Deliver a SINGLE image of ONE instant, not multiple poses."""


# Each entry is one distinct instant. Contact assignments are kept continuous
# across the cycle: near hind -> far hind -> far fore -> near fore. The farther
# foreleg trails and the nearer foreleg leads; hind lead/trail order reverses.
# These are art-direction descriptions, not inverse-kinematic target data.
POSES = [
    ("gathered_aerial", "모은 공중 자세", "All four paws are off the floor. Both forelegs are comfortably folded below the chest, forepaws pointing down and slightly back; elbows remain low and naturally attached. Both hindlegs are tucked beneath the abdomen with knees forward and hocks folded. The spine is gently flexed. Keep the near and far paws separately readable; this is the start of the collected aerial phase, not a standing or trotting pose.", []),
    ("gathered_aerial", "모은 자세에서 뒷발 내리기", "Continue the compact aerial shape. The near hind knee remains forward while its hock begins to open and the paw moves a little lower toward the floor. The far hindleg remains more folded and slightly behind it. Forelegs remain folded under the chest. Body height and spine shape change only a little from the preceding instant.", []),
    ("hind_reach", "뒷발 착지 준비 1", "The near hind paw reaches down beneath the front of the pelvis, with a softly bent knee and naturally unfolded hock. The far hind paw is still tucked a little higher and slightly forward. Forelegs remain lifted and curled beneath the chest, preparing their next forward swing. All four paws are still airborne; the trunk begins to descend gently.", []),
    ("hind_reach", "뒷발 착지 준비 2", "The near hind paw is now lower, approaching the studio floor beneath the pelvis and a little toward the head. The far hindleg follows with its knee flexed and paw higher. Both forepaws remain off the floor and clearly distinct. The back remains softly rounded, without an exaggerated arch.", []),
    ("hind_reach", "첫 뒷발 착지 직전", "The near hind paw hovers just above the floor, ready to land. Its knee and hock stay slightly flexed rather than locked straight. The far hind paw follows higher and a little farther toward the head. Both forelegs are still in aerial recovery under the chest. This is almost hind touchdown, with no forepaw touching.", []),
    ("hind_touchdown", "가까운 뒷발 착지", "The near hind paw makes the FIRST hind contact beneath and a little ahead of the hip, flat enough to support weight. The near knee and hock begin to compress naturally. The far hind paw remains just off the floor and slightly ahead of the near paw. Both forelegs are lifted and starting to unfold toward the head.", ["near_hind"]),
    ("hind_loading", "첫 뒷발 하중", "The near hind paw supports the descending pelvis; its knee and hock flex a little more. The far hind paw approaches the floor farther toward the head than the near paw. Forelegs open modestly forward and downward while remaining airborne. The chest stays stable, and the abdomen remains gently gathered.", ["near_hind"]),
    ("hind_touchdown", "먼 뒷발 착지", "The far hind paw makes the SECOND hind contact slightly farther toward the head than the already grounded near hind paw. Both hindlegs now support the body with softly flexed knees and hocks. The forelegs begin extending ahead of the chest, with separate near and far paws. No forepaw is grounded.", ["near_hind", "far_hind"]),
    ("hind_support", "두 뒷발 지지", "Both hind paws remain on the floor. The pelvis moves forward relative to their support, so the near hindleg starts extending behind the hip while the far hindleg remains more compressed beneath it. Forelegs reach a little farther forward, elbows opening below the shoulders. The trunk begins lengthening from the collected shape.", ["near_hind", "far_hind"]),
    ("hind_propulsion", "뒷다리 밀기 1", "The near hindleg extends rearward against its grounded paw, and the far hindleg takes increasing support beneath the pelvis. Both forelegs continue their forward reach with soft wrists and natural paw orientation. The back straightens gradually and the chest starts to rise; no sudden jump in body height.", ["near_hind", "far_hind"]),
    ("hind_propulsion", "뒷다리 밀기 2", "The near hind paw rolls onto its toes behind the pelvis, nearing lift-off; the far hind paw is still securely grounded and its hip, knee and hock extend in propulsion. Forepaws now reach ahead of the head-side chest while remaining airborne. The dog lengthens smoothly, with a restrained rise of the torso.", ["near_hind", "far_hind"]),
    ("hind_liftoff", "가까운 뒷발 떼기", "The near hind paw has just lifted off and trails naturally behind the pelvis. The far hind paw remains on the floor farther behind the hip, bearing the final hind support. Both forelegs extend forward with a small timing offset. Keep natural bends in the elbows and hocks, not rigid straight rods.", ["far_hind"]),
    ("hind_launch", "마지막 뒷발 추진", "Only the far hind toes remain in contact as that leg pushes the dog forward and up; the near hindleg follows airborne behind it. The forelegs reach farther ahead, the near forepaw a little ahead of the far one. The spine approaches a gently extended shape, while the head remains level and alert.", ["far_hind"]),
    ("hind_launch", "뒷발 이륙 직후", "The far hind toes have just left the floor. All four paws are now airborne. Both hindlegs extend rearward in a natural stagger while both forelegs reach toward the head-side front. The torso is starting the extended aerial phase, not a simultaneous four-leg bound.", []),
    ("extended_aerial", "뻗은 공중 자세 1", "All four paws remain off the floor. Both forelegs reach forward and slightly down, near forepaw modestly ahead of the far forepaw; both hindlegs extend behind the pelvis, with the far hind paw modestly farther back. The back is gently lengthened, and the dog forms a clear forward-reaching running silhouette.", []),
    ("extended_aerial", "뻗은 공중 자세 2", "Increase the foreleg reach and rearward hindleg stretch a little from the previous instant. The dog is fully airborne, the forepaws separated ahead of the chest and hindpaws separated behind the pelvis. Retain subtle bend at elbows and hocks, realistic limb lengths and a level head. The spine is extended but never bowed unnaturally.", []),
    ("extended_aerial", "최대 신전 접근", "The airborne body approaches its broadest natural stride. The near foreleg reaches slightly farther forward than the far foreleg, and the hind pair trails behind with a small stagger. The legs are long and reaching, yet retain visible natural joint articulation. Keep torso proportions unchanged and the abdomen realistic.", []),
    ("extended_aerial", "길게 뻗은 달리기", "Show the broad extended aerial silhouette: forelegs reaching ahead and hindlegs trailing behind, all four paws visibly clear of the floor. The nearer forepaw is slightly farther toward the head than the farther forepaw. The farther hind paw is a little farther rearward. Back gently extended, muzzle level, tail streaming naturally behind without changing its length.", []),
    ("extended_aerial", "신전 공중 정점", "Hold a near-maximum naturally stretched airborne stride with a slight progression: the far forepaw begins moving lower toward landing while the near forepaw remains a little farther forward and higher. Hindlegs are still trailing behind, and their knees begin the smallest recovery flexion. Keep all four paws off the floor.", []),
    ("fore_reach", "앞발 착지 준비 1", "The far foreleg lowers toward the floor ahead of the shoulder; the near foreleg remains farther forward and a little higher. Both hind knees begin folding from the rearward extension, bringing the hindpaws slowly inward. All four paws remain airborne. The chest descends smoothly without nose-diving.", []),
    ("fore_reach", "앞발 착지 준비 2", "The far forepaw is closer to the floor in front of the shoulder, elbow softly flexed and wrist naturally aligned. The near forepaw remains just ahead of it and slightly higher. Hindlegs trail less far back as their knees and hocks begin recovering. The body is still airborne, with a gently extended trunk.", []),
    ("fore_reach", "먼 앞발 착지 직전", "The far forepaw hovers immediately above the floor ahead of its shoulder, ready to be the first fore contact. The near forepaw is visibly separate, farther toward the head and still off the floor. Both hindlegs are airborne and beginning their forward recovery. No paw is yet pressed into the floor.", []),
    ("fore_touchdown", "먼 앞발 착지", "The far forepaw makes the FIRST fore contact ahead of the shoulder, with a natural soft elbow and aligned wrist. The near forepaw remains a little farther ahead and slightly above the floor. Hindlegs are airborne, beginning to fold beneath the pelvis. The chest starts absorbing the landing without collapsing into the foreleg.", ["far_fore"]),
    ("fore_loading", "첫 앞발 하중", "The far forepaw is grounded and begins bearing weight as the shoulder approaches over it. The near forepaw approaches the floor slightly farther toward the head than the far paw. Hind knees flex and swing forward, hocks folded comfortably. Keep a realistic smooth shoulder-to-elbow contour.", ["far_fore"]),
    ("fore_touchdown", "가까운 앞발 착지", "The near forepaw makes the SECOND fore contact farther toward the head than the far forepaw. Both forepaws now support the dog with naturally softened elbows and wrists. The hindlegs remain airborne and swing forward beneath the hips. The trunk begins gently flexing from the long airborne posture.", ["far_fore", "near_fore"]),
    ("fore_support", "두 앞발 지지 1", "The far foreleg is closer to vertical beneath its shoulder, while the near foreleg remains angled slightly forward with its paw grounded. Both front joints compress mildly under support. Hind knees swing farther forward beneath the abdomen, with distinct near and far paws. The chest lowers modestly and the spine begins gathering.", ["far_fore", "near_fore"]),
    ("fore_support", "두 앞발 지지 2", "The torso moves forward relative to the planted forepaws: the far forepaw is now slightly behind its shoulder, and the near forepaw is approaching beneath its shoulder. Both forelegs remain anatomically attached with low elbows. Hindlegs continue folding forward under the body. Back flexion increases only gently.", ["far_fore", "near_fore"]),
    ("fore_support", "앞다리 중간 지지", "Both forepaws remain grounded; the far foreleg reaches a little backward, and the near foreleg carries more support almost under the chest. Hind paws advance beneath the abdomen, near hind knee a little ahead of the far one. Maintain a natural compacting posture and stable head, with no foot sliding represented as stretched anatomy.", ["far_fore", "near_fore"]),
    ("fore_propulsion", "첫 앞발 발끝 지지", "The far forepaw rolls toward its toes behind the shoulder and is about to lift; the near forepaw still supports the body behind its shoulder with a gently extended elbow. Both hindlegs are now compact beneath the abdomen, knees forward and hocks flexed. The spine gathers for the next aerial phase.", ["far_fore", "near_fore"]),
    ("fore_liftoff", "먼 앞발 떼기", "The far forepaw has just lifted and its lower leg begins folding under the chest. The near forepaw remains on the floor behind the shoulder, providing the last strong fore support. Hind paws remain airborne beneath the belly, preparing their next landing. The chest starts rising gradually.", ["near_fore"]),
    ("fore_launch", "마지막 앞발 지지", "Only the near forepaw is grounded, farther behind the shoulder; its wrist and toes align naturally while the elbow stays below the shoulder. The far foreleg folds into aerial recovery beneath the chest. Both hindlegs are compact and swung forward under the abdomen. The back is gently rounded, not sharply bent.", ["near_fore"]),
    ("fore_launch", "가까운 앞발 발끝 지지", "The near forepaw is on its toes at the final moment of fore support behind the chest. The far forepaw is lifted and folded comfortably under the chest. Hind knees are forward beneath the abdomen and hindpaws stay clearly off the floor. The body begins lifting into gathered suspension.", ["near_fore"]),
    ("fore_liftoff", "앞발 이륙", "The near fore toes have just left the floor, so all four paws are airborne again. The near foreleg begins folding toward the already folded far foreleg. Both hindlegs are tucked beneath the abdomen with knees advanced naturally. The spine is gently flexed and the chest rises smoothly.", []),
    ("gathered_aerial", "모은 공중 자세 진입", "All four paws are airborne. Forelegs fold below the chest with the far forepaw slightly farther back than the near one. Hindlegs gather under the belly, knees forward and hocks folded, with the near hind knee slightly leading. The limbs remain separate and anatomically attached; the back flexes mildly.", []),
    ("gathered_aerial", "공중 회수 1", "The forelegs fold a little more into recovery under the chest, their paws low and slightly back. Hindlegs tuck farther forward beneath the abdomen, leaving visible separation between the near and far hocks. All four paws stay above the floor. The dog is compact but retains normal chest and belly volume.", []),
    ("gathered_aerial", "공중 회수 2", "Show a compact aerial recovery with both forepaws folded under the chest and both hindpaws tucked under the abdomen. The near hind knee is a little farther forward than the far knee; far forepaw sits a little farther back than the near forepaw. Mild spinal flexion and natural ear/fur response, without exaggeration.", []),
    ("gathered_aerial", "모은 공중 정점", "The gathered aerial configuration reaches its compactest natural instant. All four paws are off the floor, forelegs folded beneath the chest, hind knees forward and hocks tucked beneath the belly. Preserve the same body length and head proportions; create the compact silhouette through normal joint bending rather than shortening limbs.", []),
    ("gathered_aerial", "모은 자세 유지", "Continue the compact airborne recovery with only a small advance. Forepaws remain folded beneath the chest; the near hind knee starts easing downward from the deepest tuck while the far hindleg stays slightly more flexed. The back is softly rounded and the head remains level. Each paw remains separately identifiable.", []),
    ("gathered_aerial", "다음 착지로 전환 1", "The near hind hock begins unfolding a little toward the next hind landing while its knee remains forward beneath the abdomen. The far hindleg follows more slowly. Forelegs remain folded under the chest with a small timing difference. All four paws are airborne; the body begins a restrained downward arc.", []),
    ("gathered_aerial", "다음 착지로 전환 2", "The near hind paw moves modestly downward beneath the belly, still well above the floor; the far hind paw remains slightly higher. Both forelegs stay comfortably folded under the chest. The spine remains mildly flexed. Keep this instant very close to the surrounding gathered aerial poses.", []),
    ("gathered_aerial", "다음 주기 준비", "The dog remains airborne and gathered: forepaws folded below the chest, both hind knees tucked forward under the abdomen. The near hind paw starts moving lower toward the next hind touchdown and the far hindleg trails its timing slightly. Body height approaches the initial gathered pose; no paw contacts the floor.", []),
    ("gathered_aerial", "첫 프레임 직전", "This is the final instant immediately before the initial gathered aerial pose returns. All four paws remain off the floor, both forelegs folded below the chest and both hindlegs tucked beneath the abdomen. Near and far limb separation, softly flexed spine, head level, body height, tail curve and fur flow should transition gently to Frame 01, avoiding a pose jump.", []),
]


def make_catalog() -> dict:
    if len(POSES) != COUNT:
        raise ValueError(f"Expected {COUNT} separately specified poses, got {len(POSES)}")
    frames = []
    for index, (stage, label_ko, pose, contact) in enumerate(POSES):
        number = index + 1
        phase = index / COUNT
        frames.append({
            "frame": number,
            "filename": f"Frame_{number:03d}.png",
            "nominal_time_seconds": round(index / FPS, 9),
            "cycle_phase": round(phase, 9),
            "stage": stage,
            "label_ko": label_ko,
            "intended_ground_contacts": contact,
            "pose_description": pose,
            "prompt": (
                SHARED_SPEC + "\n"
                f"Stride instant: frame {number:02d} of {COUNT}, nominal phase {phase:.6f}; "
                "frame number and timing are metadata only and must NOT appear as text in the image.\n"
                f"Pose for this ONE image: {pose}\n"
                "Generate this one instant as its own complete image. Do not place any preceding or following poses in it."
            ),
        })
    return {
        "schema": "new-dog-built-in-imagegen-frame-prompts-v1",
        "generator": "tools/imagegen/border_collie_run_prompts.py",
        "mode": "built-in image_gen; one separate call for each selected frame",
        "subject": "New photorealistic black-and-white athletic Border Collie",
        "frame_count": COUNT,
        "nominal_fps": FPS,
        "nominal_period_seconds": PERIOD,
        "last_frame_time_seconds": (COUNT - 1) / FPS,
        "camera": "Fixed strict side profile, facing left",
        "background": "Matte warm-light-gray seamless studio",
        "near_limbs": {"fore": "dog left foreleg", "hind": "dog left hindleg"},
        "far_limbs": {"fore": "dog right foreleg", "hind": "dog right hindleg"},
        "qualitative_contact_order": ["near_hind", "far_hind", "far_fore", "near_fore"],
        "qualitative_cycle_order": [
            "gathered aerial", "hind landing and support", "hind launch",
            "extended aerial", "fore landing and support", "fore launch", "gathered aerial",
        ],
        "gait_reference": GAIT_SOURCE,
        "shared_spec": SHARED_SPEC,
        "limits_ko": [
            "이 파일은 프레임별 제작 지시이며 이미지 생성 또는 검수 완료 증거가 아닙니다.",
            "42장은 명목상 60fps·0.70초의 제작 순서입니다. 이미지 생성 결과의 실제 연속성은 따로 확인해야 합니다.",
            "개체·털 무늬·조명·구도와 다리의 연결·접지·프레임 간 동작을 각 이미지에서 육안으로 확인합니다.",
            "접지 단계는 예술 제작 지시이며 측정된 운동학, 물리 시뮬레이션 또는 3D 게임용 리그가 아닙니다.",
            "기존 레브라도 모델을 재사용하지 않고 한 장마다 새 이미지 생성 도구를 호출합니다.",
        ],
        "limits_en": [
            "This is a per-frame creation brief, not evidence of completed generation or review.",
            "42 frames at nominal 60 fps describe a 0.70 s art schedule; generated temporal continuity must be reviewed separately.",
            "Inspect identity, markings, framing, connected anatomy, ground contact and adjacent-frame movement for every image.",
            "Ground contacts are art-direction intent, not measured kinematics, physical simulation or a game-ready 3D rig.",
            "Do not reuse the former Labrador model; call the built-in image-generation tool separately for each frame.",
        ],
        "frames": frames,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    arguments = parser.parse_args()
    catalog = make_catalog()
    arguments.output.parent.mkdir(parents=True, exist_ok=True)
    arguments.output.write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({
        "output": str(arguments.output.resolve()),
        "frames": len(catalog["frames"]),
        "nominal_fps": FPS,
        "nominal_period_seconds": PERIOD,
        "images_generated_by_this_script": 0,
    }, ensure_ascii=False))


if __name__ == "__main__":
    main()
