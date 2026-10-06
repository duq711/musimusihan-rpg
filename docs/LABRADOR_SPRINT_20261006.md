# 영상 기준 래브라도 질주 / Video-reference Labrador sprint

사용자는 [YouTube 참고 영상](https://www.youtube.com/shorts/uOWwXi-leww?feature=share)을 제공하고 이전 질주도 어색하다고 지적했습니다. 이번 수정은 영상 첫 셰퍼드의 뻗기·앞발 지지·깊은 다리 회수·뒷발 지지의 흐름을 같은 래브라도에 적용합니다. 이전 사진 기준 인수 결과는 과거 기록으로 보존하며 이번 결과의 근거로 재사용하지 않습니다.

The user supplied the linked video and rejected the previous gallop as still awkward. This revision applies the opening Shepherd's reach, fore support, deep collection and hind support flow to the same Labrador. Prior still-reference acceptance remains historical and is not reused as evidence for this revision.

## 참고와 수정 기준 / Reference and revision criteria

원격 브라우저의 음소거·정지·프레임 이동으로 0.067~1.167초의 실제 표시 자세 12개를 확인했습니다. 약 0.70초의 화면상 주기는 움직임 속도의 참고이며 원본 촬영 속도나 실제 개의 이동 속도로 간주하지 않습니다. 영상의 속도 자막, 압축으로 흐려진 발, 품종 체형을 래브라도에 그대로 복사하지 않습니다. 원격 영상은 다운로드하거나 재배포하지 않습니다.

Twelve displayed poses were inspected through muted, paused browser frame stepping. The approximately 0.70 s displayed rhythm is a style guide, not established capture timing or animal travel speed. Speed overlays, blurred feet and breed anatomy are not copied literally. The remote video is neither downloaded nor redistributed.

기존 모션에서 확인된 주요 문제는 앞다리 도달 범위를 맞추기 위해 매 프레임 몸 전체를 즉시 낮추는 보정입니다. 회수 구간에서 골반이 두 키 동안 약 84.6mm 내려갔다가 복구되어, 안정적인 원본 캡처를 사용해도 몸통이 튀었습니다. 등·복부의 수축 대비도 작았고 뒷발 들기 회전이 급했습니다. 새 제작에서는 몸통의 연속 곡선을 먼저 만들고 어깨·가슴·다리의 국소 보정으로 도달 범위를 해결합니다.

The prior framewise global reach correction dropped and restored the pelvis by about 84.6 mm across two keys, overriding the smooth captured body trajectory. Body collection was weak and hind toe pitch changed abruptly. The new production designs continuous body trajectories first, then resolves reach with local shoulder/chest/limb fitting.

새 인수는 실제 피부의 뻗기와 깊은 회수, 짧게 엇갈리는 앞·뒷발 리듬, 연속 몸통 움직임, 발목 연결·관절 방향, 지면 접촉과 반복 경계를 함께 봅니다. 수치 검사와 시각 판단은 별도로 기록하고, 최종 모델에서 정상·반속도 순서 프레임을 검토합니다. 이전 Walk·care 키와 원본 mesh·rest·weights·morph·털 마스크는 보존합니다.

Acceptance covers extension and deep collection in actual skin, leading/trailing foot cadence, continuous core movement, anatomical attachment, ground contact and repeat boundaries. Numerical checks and visual judgments are recorded separately; normal and half-speed final-frame progression is inspected. Walk/care keys and acquired mesh/rest/weights/morph/coat mask remain unchanged.

## 산출물과 검증 / Artifacts and validation

작업 폴더 / Task directory: `asset-staging/labrador-sprint-20261006/`.

최종 Run은 0.70초·60fps·1–43프레임이며 기준 이동 속도는 2.3472m/s입니다. `production/LabradorPet_Sprint.blend`, `export/LabradorPet_Sprint.glb`, `export/Locomotion/Run.fbx`, `export/sprint-manifest.json`을 보존합니다. 원본 발 궤적을 참고하되 몸통·머리·접지 타이밍·깊은 회수·손목은 체형에 맞춰 조정·제작했습니다.

The final Run is 0.70s at60fps, frames1–43, nominal2.3472m/s. Production, combined GLB, Run FBX and manifest remain in the task directory. Source-derived paw paths guide authored body/head/contact timing/recovery/carpal fitting.

자체 31검사(85개 피부·FBX5자세), 별도 169개 실제 피부·코어·접지 표본, Unity195검사(86개 실제 피부), 새 Mac 실행본30검사를 통과했습니다. 피부 최저높이는 Blender +0.333mm / Unity +0.571mm, 고정 발바닥 중심 이동오차 최대1.67mm입니다. 앞다리 도달잔차0이며 골반 가속도는10.83m/s²로 이전 급락이 해소됐습니다. 발목·팔꿈치·무릎의 원래 굽힘 방향을 보존했습니다. 수치는 물리 힘이나 미적 승인 판정이 아닙니다.

Validation passed31 authoring checks,169 independent actual-skin/core/contact poses,195 Unity import checks and30 fresh native checks. Blender/Unity skin minima are +0.333/+0.571mm; planted sole centroid drift is at most1.67mm. IK endpoint residual is zero, pelvis acceleration10.83m/s², and original joint bend directions remain preserved. These metrics are neither force measurements nor aesthetic user approval.

최종 `export/LabradorPet_Sprint.mp4`는12초·960×640·30fps이며4초씩 정상 옆면 / 반속도 옆면 / 정상 비스듬한 시점을 제공합니다. 실제 MP4에서 정상23·반속도44·비스듬한23의 순서 프레임90개와 반복 경계를 검토했고, AVFoundation 정확 시간 이동5개를 통과했습니다. 이는 연속 프레임 검토이며 사람이 영상을 무중단 시청했다는 주장이 아닙니다. 대표 뻗기·회수 PNG2장도 최종 출력으로 보존합니다.

The final reel presents4s each of normal side, half side and normal quarter view. Ninety ordered decoded movie frames including repeat boundaries were reviewed, and5 exact AVFoundation seeks passed. This is frame progression inspection, not an assertion of uninterrupted human playback. Two final pose posters remain user-facing outputs.

실제 Unity `Run.fbx`·`Run.anim`만 교체하고 두GUID를 유지했습니다. FBX메타 외30자산/메타와 런타임3파일 해시는 그대로입니다. `unity-game/Builds/MusimusihanRPG.app`를 새 인수된 실행본으로 교체하고 Applications·Dock 연결을 유지했습니다. 빌드는 오류0·기존 공통경고171개이며 Labrador관련경고0입니다. F2의 걷기/달리기 전환·정지/재개·재시도/초기화·기존쓰다듬기·원래게임상태 복구를 확인했습니다. 실제 데스크톱 입력·포커스·오디오는 사용하지 않았습니다.

Actual Unity Run assets were replaced with both GUIDs retained. Thirty other asset/meta files and3 runtime hashes are preserved. The freshly accepted native app is installed at the canonical path with Applications/Dock links retained. Build errors0;171 existing common warnings reviewed, no Labrador-specific warning. Native F2 transition/pause/resume/retry/reset/petting/state restoration passed without desktop input, focus or sound.

로컬 미리보기는 http://127.0.0.1:8773/locomotion/ 에서 새 Sprint를 재생합니다. GLB·manifest·기존쓰다듬기모델 HTTP해시3개, 시간 이동(.2/.7), 배속·시점·Walk전환·재생재개, 콘솔경고/오류0을 확인했습니다. 이전 사진 기준 인수와32개fixture는 이번 새질주의 근거로 재사용하지 않았습니다.

The local viewer serves the new Sprint with3 exact asset-hash matches, seek/rate/view/Walk/resume controls and no console warnings/errors. Prior photo-based acceptance and32 fixtures were not counted as evidence for this revision.

작은 근거: `sprint-summary.json`, `sprint-production-summary.json`, `sprint-independent-numerical-summary.json`, `sprint-root-visual-review.json`, `sprint-unity-import.json`, `sprint-native-acceptance.json`, `sprint-native-install.json`, `sprint-video-summary.json`, `sprint-video-seek.json`, `sprint-viewer-validation.json`. 이번 정리·GitHub원격확인은 별도 영수증에 기록합니다. 공개에는 제작도구·문서·검사 요약만 포함하며 licensed binary는 로컬에 보존합니다.

Compact receipts preserve source-bound production/skin/reference/import/native/video/viewer evidence. Cleanup and verified remote publication are recorded separately. Production tools/docs/receipts are public; licensed binaries remain local.

검증 정리: 297파일, 할당 3.376GB 제거. 관측된 여유공간 증가는 3.337GB, 현재 17.763GB입니다. APFS공유블록·동시쓰기로 두수치를 구분합니다. 새 최종출력·현재실행본·원본·재사용도구와 현재Editor운영로그를 보존했습니다.

Cleanup removed 297reviewed files, 3.376GB allocation. Observed free-space increase 3.337GB; free space now 17.763GB. APFSsharing/concurrent writes distinguish these figures. Final artifacts/current app/source/reusable tools and the resident Editor operational log remain preserved.

GitHub코드체크포인트: [`16f54b66`](https://github.com/duq711/musimusihan-rpg/commit/16f54b668c84bc490dd26ef2d16abd201f7d60e7) / `codex/labrador-pet-20261005`. GitHub ref·fetch한원격·로컬task ref가일치하며선택37개blob을대조했습니다. 현재작업HEAD와sharedindex는변경하지않았습니다. 마지막문서·영수증추가커밋은 publication영수증에이어기록합니다.

GitHub code checkpoint: 16f54b668c84bc490dd26ef2d16abd201f7d60e7. GitHub ref, fetched remote and local task ref match, with37 selected blob hashes verified. Current worktree HEAD/shared index remain unchanged. A final documentation/receipt commit records this verification.

## 사용자 지적 후 확인된 변형 결함 / Confirmed deformation after user feedback

2026-10-06 사용자 화면의 0.63/0.70초(phase .90) 앞다리 변형을 다시 조사했습니다. 위 제작의 전체 피부품질 채택은 철회합니다. 앞선 접지·반복·기능검사의 통과는 보존하되 자연스러운 어깨 형태나 몸통 비침범을 보증하지 않습니다. 기존 시각 검토에서 이 결함을 놓쳤습니다.

At .63/.70s, the user's screenshot exposed malformed forelegs. Overall skin-quality acceptance is withdrawn. Earlier support/loop/native functional results remain historical facts, but do not establish shoulder shape or absence of self-intersection. Visual review missed this defect.

상완이 neutral보다 좌131.23°/우124.55° 회전해 팔꿈치가 어깨보다89.84/82.27mm 높아집니다. 손목 회수목표와 어깨 뒤쪽이동을 두본IK가 발끝 중심으로 풀면서 상완을 가슴 위·안쪽으로 접었습니다. 팔꿈치의 굽힘 부호가 맞아도 상완 방향·몸통간섭은 틀릴 수 있습니다. 혼합 스킨이 잘못된 자세를 따라 늘고 압축되어 혹과 파묻힘이 발생합니다.

The endpoint-driven two-bone solution combines wrist recovery targets and posterior shoulder glide, rotating upper arms131.23°/124.55° and raising elbows89.84/82.27mm above shoulders. Correct elbow bend sign does not constrain humerus orientation or torso clearance. Blended skin follows this bad pose and bulges/collapses.

비인접 가슴·앞다리 표면의 실제 edge–triangle 교차는 neutral0 / 이자세198쌍이며, 선택한 다리표면80삼각형의 면적이 neutral20%미만으로 압축됐습니다. 별도 torso/neck/통합fore영역 BVH검사는 neutral0 / 이자세232쌍을 확인했습니다. 영역·방법이 달라 합산하지 않으며 전체mesh 충돌량이나 침범깊이가 아닙니다. 근거는 `sprint-deformation-diagnosis.json`, 재사용검토도구는 `tools/dcc/diagnostics/labrador_sprint_deformation_probe.py`입니다.

Exact edge–triangle probing found0 neutral versus198 selected nonadjacent chest/foreleg crossing pairs, with80 selected triangles below20% neutral area. Independent torso/neck/combined-fore BVH selection found0 versus232 pairs. These different selections are not summed and do not measure penetration depth or all-mesh collisions. The compact diagnosis and preserved probe retain the evidence.

이 요청은 원인 진단이며 제작원본·출력·Unity자산·실행본을 수정하지 않았습니다. 후속 수정은 손목회수·어깨·상완방향·가슴밖 여유를 함께 제약하고 전주기의 자기교차와 접합부피부를 다시 확인해야 합니다.

This request diagnoses the cause; production/exports/Unity assets/player remain unchanged. A correction requires joint wrist/shoulder/humerus constraints, chest clearance and whole-cycle self-intersection/junction-shape review.
