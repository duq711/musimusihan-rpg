# 플레이어 360° 모델 뷰어 / Player 360° model viewer

현재 게임의 `godot-game/assets/3d/player/gravebound_player.glb`를 직접 불러오는 로컬 제작 검수 도구입니다. 모델 복사본이나 정지 이미지가 아니며 게임 데이터는 수정하지 않습니다. 브라우저용 조명을 사용하므로 Godot 렌더와 밝기는 다를 수 있습니다.

English: A local review tool that loads the current game GLB directly, with no model copy or game-state changes. Browser lighting may differ from Godot.

프로젝트 루트에서 실행 / Run from project root:

```sh
python3 tools/player-model-viewer/server.py --port 8768
```

브라우저에서 http://127.0.0.1:8768 을 엽니다. 서버는 localhost에만 연결하며 종료는 Ctrl+C입니다. 모델 수정 후 브라우저를 새로고침하면 최신 파일이 적용됩니다.

English: Open http://127.0.0.1:8768. The server binds to localhost only; stop with Ctrl+C. Refresh after asset edits to load the latest model.

- 왼쪽 드래그: 360° 회전 / Left drag: free orbit.
- 휠: 확대·축소 / Wheel: zoom.
- 오른쪽 드래그 또는 Ctrl+왼쪽 드래그: 이동 / Right drag or Ctrl+left drag: pan.
- 손 확대, 정면·후면·측면, 전신 맞춤, 자동 회전 / Hand focus, preset views, fit and auto-rotation.
- 머리 확대: 후드를 제거한 머리와 얼굴을 가까이 봅니다. / Head focus: inspect the exposed head and face.
- 어깨 연결: 후드 천을 제거한 목과 소매 연결을 높은 사선에서 살펴봅니다. / Shoulder join: inspect the exposed neck and sleeve joins from above.
- 터치: 한 손가락 회전, 두 손가락 확대·이동 / Touch: one finger orbit, two fingers zoom/pan.

Three.js 0.170.0의 필요한 파일만 vendor에 고정 포함했습니다(MIT, vendor/LICENSE). 런타임 외부 CDN 요청은 없습니다.

English: Required Three.js 0.170.0 files are vendored under MIT (vendor/LICENSE), with no external CDN requests at runtime.

검증 / Validation: Codex 실제 브라우저에서 모델 로드, 드래그 회전, 휠 확대·축소, 손 확대 및 전신 맞춤을 확인했습니다. 사용자가 제공한 머리·눈 모델로 교체하는 최신 작업의 검증 상태는 [제공 모델 검증 기록](../../asset-staging/player_supplied_face_20260921/VALIDATION.md)에 기록합니다. 범용 라이브러리의 오른쪽 드래그 이동 경로는 코드에서 확인했습니다.

English: Verified loading, drag orbit, wheel zoom, hand focus and full-body reset in the live Codex browser. Current supplied-head replacement status is recorded in the [validation document](../../asset-staging/player_supplied_face_20260921/VALIDATION.md). Right-drag pan uses the library's standard controls and was checked in code.

최신 의상 변경 / Latest outfit change: [목·어깨 후드 제거 검증](../../asset-staging/player_cowl_removed_20260922/VALIDATION.md).

목·어깨 연결 재구성 / Rebuilt neck and shoulder joins: [구조·화면 검증](../../asset-staging/player_natural_shoulders_20260922/VALIDATION.md).

- 상체 비율: 목·어깨·가슴을 사선 정면에서 확인합니다. / Upper-body view: inspect neck, shoulders and chest from the front oblique.
- 형태 확인: 색상과 무늬를 잠시 끄고 무채색으로 형태를 봅니다. 다시 누르면 원래 재질로 돌아옵니다. 게임 에셋은 변경하지 않습니다. / Shape inspection toggles neutral clay shading and restores the original materials, without modifying the game asset.

코트 자락 제거 및 바지 완성 / Coat-tail removal and completed trousers: [하의 검증 기록](../../asset-staging/player_trousers_only_20260922/VALIDATION.md). 전신 맞춤으로 변경된 복장을 확인합니다. Use Fit body to inspect the updated outfit.

가슴·등·어깨·위팔 형태 수정 / Resculpted chest-to-arm transitions: [형태 검증 기록](../../asset-staging/player_shoulder_form_20260922/VALIDATION.md). 상체 비율과 형태 확인 버튼으로 검토합니다. Use Upper-body view and Shape inspection for review.

2026-09-22 복원 / Restoration: 사용자 요청으로 마지막 어깨 조형을 철회하고 `f279eec` 모델로 복귀했습니다. 복원 시점 게임 GLB SHA256: `f7ad57eddd4ac751daee53fcdb05bf627a749007f0989d9f344f735dfb2e2a77`. The viewer serves the restored previous model, preserving the face, hands and trousers. Evidence: [복원 기록](../../asset-staging/player_shoulder_rollback_20260922/VALIDATION.md).

2026-09-22 목·어깨 보강 / Sturdier neck and shoulders: 복원본에서 목 두께와 어깨 폭만 보강했습니다. 팔·손의 원래 형상을 유지합니다. Thicken the neck and broaden the shoulder frame on the restored model while preserving the original arm/hand shapes. [제작·검증 / Production and validation](../../asset-staging/player_sturdy_neck_shoulders_20260922/VALIDATION.md).

2026-09-22 목·어깨 흐름과 소매 연결 / Neck, shoulder and sleeve flow: 듬직한 체격과 기존 팔꿈치·전완을 보존하고 목·어깨 접합부와 상부 소매 원단을 다듬었습니다. 상체 비율에서 재질을 확인하고 형태 확인으로 조형을 살펴봅니다. Preserve the sturdy build and lower-arm shape while refining the neck, shoulder joins and upper-sleeve fabric. [제작·검증 / Production and validation](../../asset-staging/player_neck_arm_flow_20260922/VALIDATION.md).

2026-09-22 참조 체형 비율 / Reference-guided proportions: 제공 사진을 참고해 흉곽·어깨 폭과 경사·위팔·팔꿈치 높이를 함께 조정했습니다. **상체 비율**과 **형태 확인**으로 검토할 수 있습니다. Refit the chest, shoulder frame and slope, upper arms and elbow placement from the supplied reference. Use Upper-body view and Shape inspection. [제작·검증 / Production and validation](../../asset-staging/player_reference_anatomy_20260922/VALIDATION.md).

2026-09-22 전신 4방향 비율 / Four-view full-body proportions: 전신의 허리·골반·팔·다리·부츠까지 함께 맞췄습니다. **사진 비율 비교**를 누르면 정면·후면·양측면 사진과 실제 게임 렌더를 슬라이더·실루엣 윤곽으로 비교합니다. 뷰어 서버는 검토 페이지와 명시한 참조·렌더 파일만 추가 제공하며 전체 리포지터리를 공개하지 않습니다.

English: Fit the complete waist, pelvis, arms, legs and boots. **Photo proportion comparison** opens four-view reference/render wipes and silhouette overlays. The local server exposes only the explicitly listed review artifacts. [제작·검증 / Production and validation](../../asset-staging/player_multiview_proportions_20260922/VALIDATION.md).


### 겨드랑이 연결 비교 / Axilla review

`/?view=axilla` opens the current game model at the refined chest/upper-arm junction. `겨드랑이 확대` focuses that area; free rotation, zoom and shape mode remain available. `/axilla/compare.html` compares the preserved baseline and final actual Godot renders at identical front, oblique and rear cameras, in cloth and clay modes. Only those 12 named images are served.

겨드랑이 확대와 수정 전후 비교를 추가했습니다. 전신 비율을 보존하고 깊은 홈을 완화한 결과와 검증은 `asset-staging/player_axilla_refinement_20260922/VALIDATION.md`에 기록했습니다. The approved full-body proportions are retained; the production asset, source and validation are documented there.


### T자 자세 / T pose

`/?pose=t`로 현재 모델의 T자 자세를 엽니다. `T자 자세` 버튼으로 원래 자세와 전환할 수 있고, 회전·확대·전신 맞춤도 유지됩니다. 뷰어에서 팔과 손을 수평으로 펼치는 확인용 자세이며, 게임 GLB 파일은 변경하지 않습니다. 원본 메시 버퍼를 보존하므로 반복 전환해도 변형이 누적되지 않습니다.

Open `/?pose=t` to inspect the current model in a T pose. The T-pose button toggles back to the exact source geometry; free rotation, zoom and fit remain available. This is a reversible viewer inspection pose for the static asset, not an animation-ready skeleton or a replacement game asset. The shoulder transition includes a local cloth correction for raised arms.

2026-09-22 T자 팔 수정 / T-pose anatomy correction: 기존 T자 변형에서 팔꿈치가 위팔보다 굵어지고 어깨가 꺼지며 겨드랑이 안쪽이 접혀 내려가던 문제를 수정했습니다. 참조 사진에 맞춘 단면, 쇄골·어깨 연결, 접합선 아래의 소매 접힘 보정과 공통 경계 표면 정리를 적용했습니다. 이는 정적 게임 모델의 **검토용 자세 보정**이며, 게임 원본 자세나 애니메이션 리그를 교체하지 않습니다.

The corrected inspection pose uses reference-guided cross-sections, a restored collar-to-deltoid transition, a constrained inner-underarm fold and shared-boundary surface relaxation. The production rest pose remains unchanged; this is not an animation-ready rig.

검증 / Validation: `node tools/player-model-viewer/pose.test.mjs` measures actual triangle-plane sections from the production GLB. It checks upper-arm/elbow/forearm proportions, taper in two axes, shoulder height, inner underarm folds, shared joins, finite deformation, positive field Jacobians, exact repeated reset and unchanged source hash. It also catches the rejected previous silhouette. Final measurements and actual front/oblique/rear renders: [제작·검증 기록 / Production and validation](../../asset-staging/player_tpose_anatomy_20260922/VALIDATION.md).
