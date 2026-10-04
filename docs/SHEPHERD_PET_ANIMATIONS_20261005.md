# 독일 셰퍼드 펫 모션 / German Shepherd pet animations

2026-10-05, Mac 제작 / Produced on this Mac.

사용자가 선택한 무료 RetroStyle 독일 셰퍼드를 내려받아 **펫 동작 13개를 추가하고 총 16개 클립**을 제작했습니다. Mac Blender 5.2.1 LTS 제작본, 개별 FBX, Unity 6000.3.25f1 Built-in 패키지를 로컬에 보존했습니다. 원본 메시를 다시 모델링하거나 털을 새로 제작한 작업은 아니며, 외형은 2,272삼각형·2K 텍스처의 원래 게임용 모델입니다.

Downloaded the selected free RetroStyle German Shepherd and added 13 pet motions, producing 16 clips in total. The Mac Blender 5.2.1 LTS source, separate FBXs and a Unity 6000.3.25f1 Built-in package are preserved locally. This extends the original 2,272-triangle/2K game model; it does not replace its mesh or produce new fur.

## 최종 산출물 / Final artifacts

프로젝트 루트 기준 / Relative to the repository root:

| 경로 / Path | 내용 / Content |
| --- | --- |
| `asset-staging/shepherd-pet-20261005/source/` | 원본 ZIP·FBX·텍스처 보존 / Preserved original archive, FBXs and textures |
| `asset-staging/shepherd-pet-20261005/production/ShepherdPet_Animations.blend` | 텍스처를 포함한 편집 가능한 제작본·원본 Action 보존 / Editable packed source and retained original Actions |
| `asset-staging/shepherd-pet-20261005/export/ShepherdPet_BuiltIn.unitypackage` | 16클립·공유 Generic Avatar·Standard Cutout 재질·프리팹·Animator·MouthSocket / 16 clips, shared Avatar, materials, prefab, Animator and mouth socket |
| `asset-staging/shepherd-pet-20261005/export/ShepherdPet_Model.fbx` 및 `Animations/` | 모델과 동일한 리그를 포함한 개별 클립 FBX / Model and individual clips with matching hierarchy |
| `asset-staging/shepherd-pet-20261005/motion-manifest.json` | 길이·반복·접촉 이벤트·제작 보정값 / Duration, loop, contact events and authoring corrections |
| `asset-staging/shepherd-pet-20261005/source-manifest.json` | 출처·다운로드 날짜·원본 해시 / Provenance, date and archive hash |

Unity 패키지는 **26,410,681바이트**, SHA-256 `3fcb4c3eb74741352c046915a11760252d8034f9bde028f65dfb72c685851989`입니다. Unity의 Import Package로 가져오면 `Assets/ShepherdPetLocal/Prefabs/ShepherdPet.prefab`을 사용할 수 있습니다. Animator에는 동작별 state가 있으며 기본 상태는 IdleFriendly입니다. 자동 행동 전환은 게임 로직에서 연결해야 합니다.

The package is 26,410,681 bytes with the SHA-256 above. Import it to use `Assets/ShepherdPetLocal/Prefabs/ShepherdPet.prefab`. The Animator has a state per clip and defaults to IdleFriendly; automatic behavior transitions need gameplay code.

## 클립 / Clips

모두 30FPS, Generic, 제자리 동작입니다. 골반의 작은 체중 이동·상하 움직임은 포함하지만 누적 이동은 없습니다. / All clips use 30 FPS, Generic and in-place motion, including small body weight shifts without cumulative travel.

| 클립 / Clip | 초 / Seconds | 반복 / Loop | 용도 / Use |
| --- | ---: | --- | --- |
| IdleFriendly | 3.0 | Yes | 숨쉬기·편안한 꼬리 / Breathing, relaxed tail |
| Walk | 0.6 | Yes | 걷기 / Walking |
| Run | 0.4 | Yes | 달리기 / Running |
| CombatBite | 1.2 | No | 물기, 접촉 메타데이터 0.60s / Bite, contact metadata at 0.60s |
| SearchSniff | 3.0 | Yes | 제자리 냄새 탐색 / Stationary sniffing |
| SearchWalk | 1.8 | Yes | 천천히 냄새 맡으며 걷기 / Slow scent walking |
| SearchFound | 1.5 | No | 발견 후 주인에게 알림 / Finding cue |
| RetrievePickup | 1.5 | No | 줍기, 붙이기 메타데이터 0.80s / Pickup, attach metadata at 0.80s |
| RetrieveCarryWalk | 1.2 | Yes | 입을 닫고 운반 보행 / Closed-jaw carrying walk |
| RetrieveDrop | 1.5 | No | 놓기, 떼기 메타데이터 0.80s / Drop, detach metadata at 0.80s |
| EatStart | 1.0 | No | 먹이 쪽으로 숙이기 / Lower to food |
| EatLoop | 2.0 | Yes | 씹기 / Chewing |
| EatEnd | 1.0 | No | 고개 들기 / Raise head |
| PetSit | 1.5 | No | 앉기 / Sit |
| PetEnjoy | 3.0 | Yes | 쓰담 반응·고개 기울이기·꼬리 / Petting reaction, tilt, wag |
| PetRise | 1.2 | No | 일어나기 / Rise |

기본 이동은 제작사 동작을 재사용·보정했고 추가 모션은 해당 DEF 리그에 키를 제작했습니다. 앉기·숙이기는 체인 길이를 유지하는 발 접지 IK로 베이크했습니다. 품종에 맞춰 꼬리 방향을 보정했고 반복 관절의 위치·쿼터니언 접선을 맞췄습니다. 반복 경계의 최소 발 높이 보정은 걷기 3.4mm·달리기 41mm이며 manifest에 기록합니다. 실제 이동 속도와 발 미끄러짐은 게임의 이동 제어와 함께 맞춰야 합니다.

Locomotion reuses and corrects the publisher's motions; additional keys were authored on its DEF rig. Sitting/lowering uses baked contact IK without stretching. Tail attitude and loop tangents were corrected. The seam clearance lift is recorded in the manifest, including 3.4mm for walking and 41mm for running. Match travel speed and evaluate foot sliding with the game's movement controller.

먹기 순서는 EatStart → EatLoop → EatEnd, 교감 순서는 PetSit → PetEnjoy → PetRise입니다. MouthSocket은 `DEF-spine.011`을 따라가며 실제 아이템 크기에 맞춰 위치를 조절해야 합니다. 이벤트는 메타데이터로만 보존했고 미구현 AnimationEvent 수신 함수를 추가하지 않았습니다.

Use EatStart → EatLoop → EatEnd and PetSit → PetEnjoy → PetRise. MouthSocket follows `DEF-spine.011`; adjust it to actual item dimensions. Events remain metadata without unimplemented AnimationEvent receivers.

## 확인한 결과와 한계 / Validation and limits

- Blender: 16클립·30FPS·55개 뼈의 유한 변환·778개 정수 프레임 자세 및 실제 메시·8루프 끝 자세/접선·먹기/교감 4경계 통과. 정지 발 최대 오차 약 0.002mm, 최저 메시 Z −1.831mm로 −2mm 허용 범위 내. / Passed 16 clips, 30 FPS, finite bone transforms, 778 pose and mesh frames, eight loop endpoints/tangents and four action boundaries. Stationary toe error is about 0.002mm; minimum mesh Z is −1.831mm within the −2mm tolerance.
- FBX: 16개 재임포트·48개 자세 비교 통과, 최대 위치 차이 약 0.0017mm. 제작본 해시 불변. / Passed 16 roundtrips and 48 pose comparisons with about 0.0017mm maximum positional difference; production source hash unchanged.
- Unity: 6000.3.25f1 격리 Editor의 464,215개 수치·연결 검사 통과, 실패 0. 16 Generic 클립, 9,072곡선 연결, 실제 CPU 스킨 변형 80회. 2,272삼각형·55뼈·재질 법선/거칠기 변환·프리팹/소켓 확인. / Passed 464,215 isolated numerical/binding checks, 16 Generic clips, 9,072 bindings and 80 CPU skin samples, including geometry/material/prefab/socket checks.
- 패키지: 30개 항목, 17개 FBX, 제작 파일 21개 SHA-256 일치 확인. / Verified 30 entries, 17 FBXs and 21 production-file hashes.
- 시각 검토: 전투/탐색·회수·먹기·교감·이동의 옆면 57자세와 이전 정면/사선 표본을 검토했습니다. 원본 이동은 게임용 표현이며 실사 모션캡처를 리타기팅한 결과는 아닙니다. / Reviewed 57 side poses across combat/search, retrieval, feeding, care and locomotion, plus earlier front/three-quarter samples. Locomotion is the source game's style, not newly retargeted real-dog mocap.
- 이 검사는 모든 정수 프레임과 일부 FBX 비교 표본을 확인합니다. 프레임 사이 피부 침투·해부학적 자연스러움·실제 이동 속도/소품 접촉은 별도 조정 대상입니다. Unity renderer bounds는 skinned bounds로 실제 체고와 구분합니다. / Interframe skin penetration, anatomical quality, travel speed and prop contact remain separate tuning concerns. Imported skinned bounds are not an anatomical height measurement.
- 모션 자산 제작을 완료했으며 전투 판정·탐색/회수 AI·먹이 시스템·주인공 손 모션·메인 게임/F2 통합은 이번 범위에 포함하지 않았습니다. / This completes the motion asset task, not combat logic, retrieval AI, feeding systems, player hand animation or game/F2 integration.

## 출처·공개 범위 / Source and publication

[RetroStyle Games 공식 itch.io](https://retrostylegames.itch.io/german-shepherd-3d-dog-model-free)는 개인·상업 프로젝트 무료 사용을 명시합니다. 해당 공개 Download 버튼으로 FBX ZIP을 받았으며 로그인·결제·Discord 가입은 하지 않았습니다. 원본 ZIP은 19,422,656바이트, SHA-256 `19588eca88d4b03aefa7d1d8a6e3aebc774eb636bb95af9c846d446f89f75ea9`입니다.

The official page explicitly offers free personal/commercial project use. The FBX ZIP was downloaded through its public Download button without login, payment or Discord membership. The archive's byte count and SHA-256 are above.

원본 재배포 권한은 별도 확인되지 않았으므로 원본 ZIP·모델·모델을 포함한 제작본/FBX/Unity 패키지는 공개 Git에서 제외합니다. 공개 대상은 직접 작성한 제작·IK·검수·프리뷰 도구, 출처와 동작 manifest, 문서입니다. 로컬 최종 산출물과 GitHub에 공유한 도구/문서를 구분합니다.

Standalone redistribution permission was not separately granted, so licensed archives, models and model-containing Blender/FBX/Unity packages stay out of public Git. Public files are authored production/IK/validation/preview tools, provenance/motion manifests and documentation. Local production assets and published tools/docs are distinct.

## 재제작 / Reproduction

직접 받은 ZIP을 `source/`에 보존·풀고 이 Mac에서 아래 명령을 실행합니다. 원본은 덮어쓰지 않습니다. / Preserve and extract your downloaded archive under `source/`, then run on this Mac without overwriting originals.

```sh
/Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup --disable-autoexec --python tools/dcc/shepherd_pet.py -- --base asset-staging/shepherd-pet-20261005
/Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup --disable-autoexec --python tools/dcc/shepherd_pet_validate.py -- --base asset-staging/shepherd-pet-20261005
```

Unity 검수기는 `tools/dcc/ShepherdPetImportValidator.cs`입니다. 지정 marker를 가진 작은 격리 프로젝트에서만 실행하도록 제한했습니다. 메인 게임 프로젝트에 넣지 않습니다. / The Unity validator requires a marked disposable project and refuses main-project import.

## 완료 후 정리 / Completion cleanup

검수 캡처·로그·중간 Blender 저장본·격리 Unity 캐시 **452개 파일**을 결과 요약 보존 후 제거했습니다. 제거한 파일 할당량은 **162,541,568바이트(155.0MiB)**, 논리 파일 크기는 160,396,488바이트입니다. 정리 직후 디스크 여유는 **14,049,280,000바이트(13.08GiB)**, 관측 증가량은 163,840,000바이트입니다. APFS 공유 블록과 다른 시스템 작업 때문에 파일 할당량과 여유 공간 변화는 다를 수 있습니다. 원본, 최종 `.blend`/FBX/Unity 패키지와 패키지 안 importer metadata, 재사용 도구와 기존 플레이용 앱은 보존했습니다. 작은 영구 기록은 `asset-staging/shepherd-pet-20261005/completion-summary.json`입니다.

Removed 452 reviewed capture/log/intermediate/cache files after preserving the summary: 155.0MiB allocated, 160,396,488 logical bytes. Free space measured immediately afterward was 13.08GiB, with 163,840,000 bytes of observed increase. APFS sharing and concurrent system work can make allocation differ from free-space changes. Originals, final source/exports/package with importer metadata, reusable tools and the existing playable app are retained. The compact permanent record is `completion-summary.json` at the path above.

## 요청한 모션 영상 / Requested motion video

사용자가 모션을 영상으로 보여달라고 요청하여, 기존 제작본의 16클립을 순서대로 보여주는 MP4 쇼릴을 완성했습니다. **960×640, 24FPS, 759프레임, 31.625초**, H.264, 무음입니다. `tools/dcc/shepherd_pet_video.py`가 걷기·달리기·냄새 탐색·물기·회수·먹기·교감 동작을 옆면과 사선 카메라에서 한국어·영어 자막과 함께 보여줍니다. 먹기는 EatStart → EatLoop → EatEnd, 교감은 PetSit → PetEnjoy → PetRise 순서입니다.

Completed the requested MP4 showreel of all 16 existing clips: **960×640, 24 FPS, 759 frames, 31.625 seconds**, H.264 and no audio. `tools/dcc/shepherd_pet_video.py` shows locomotion, search, biting, retrieval, feeding and petting reactions from side and three-quarter cameras with Korean/English captions. Feeding follows EatStart → EatLoop → EatEnd; care follows PetSit → PetEnjoy → PetRise.

영상 경로는 `asset-staging/shepherd-pet-20261005/export/ShepherdPet_Motions.mp4`, 완료 기록 경로는 같은 제작 폴더의 `video-summary.json`입니다. 제작 도구는 원본 `.blend`를 읽고 메모리에서 쇼릴 Action·무대·카메라·자막을 만든 뒤 직접 MP4를 렌더링했습니다. 원본 저장 없이 제작본 SHA-256 불변을 확인했습니다. 영상은 **4,117,921바이트**, SHA-256 `239134fc7062d4421ffbf7e01d0c7dba337c817003cb2241eb28b8093a2af430`입니다. Mac AVFoundation으로 시작·중간·끝의 5표본을 디코딩하여 크기·길이·프레임 속도와 읽을 수 있는 자막을 확인했고, 16클립의 연속 759프레임 구성을 검사했습니다. 시각 검토는 표본 검사입니다.

The output path is `asset-staging/shepherd-pet-20261005/export/ShepherdPet_Motions.mp4`, with its completion receipt at `video-summary.json` in the same production folder. The tool rendered an in-memory showreel without saving the source; the production SHA-256 stayed unchanged. The video is **4,117,921 bytes** with the SHA-256 above. Mac AVFoundation decoded five beginning/middle/end samples, confirming dimensions, duration, frame rate and readable captions. All 16 clips form a contiguous 759-frame timeline. Visual review is sampled.

이 영상은 사용자가 명시적으로 요청한 최종 산출물이므로 보존합니다. 검수용 추출 프레임과 임시 로그는 검토 후 정리합니다. 렌더된 영상과 모델을 포함한 바이너리의 재배포는 구분하며, 원본 ZIP·`.blend`·FBX·Unity 패키지는 기존 공개 제외 원칙을 유지합니다. 영상은 만들어 둔 모션의 재생이며 전투 판정·탐색/회수 AI·아이템·먹이·주인공 손과의 상호작용을 시뮬레이션하지 않습니다.

The requested video is a final deliverable and is preserved; extracted review frames and temporary logs are cleaned after inspection. A rendered video is distinct from redistribution of model-containing binaries: original archives, `.blend`, FBX and Unity packages remain excluded from public Git. This showreel plays authored motions without simulating combat, retrieval AI, items, food or the player's hand interaction.

이번 영상 검수의 임시 프레임·로그·Swift 디코더/컴파일 캐시 **261개 파일**을 정리했습니다. 제거한 파일 할당량은 **260,997,120바이트(248.9MiB)**, 논리 크기는 260,442,936바이트입니다. 직후 여유 공간은 **16,629,760,000바이트(15.49GiB)**, 관측 증가량은 245,760,000바이트입니다. APFS 공유 블록과 다른 작업에 따라 할당량과 실제 여유 공간 변화가 다를 수 있습니다. 최종 영상·원본·Unity 패키지·재사용 도구·기존 플레이용 앱을 보존했습니다. 이번 공개 Git 변경은 렌더 도구·문서·영상 요약이며 MP4는 로컬 산출물입니다.

Removed **261** temporary review frames, logs, Swift decoder and compiler-cache files: **260,997,120 allocated bytes (248.9MiB)** and 260,442,936 logical bytes. Free space immediately afterward was **16,629,760,000 bytes (15.49GiB)**; the observed increase was 245,760,000 bytes. APFS sharing and concurrent work can make these values differ. The final video, original source, Unity package, reusable tools and existing playable app are preserved. This public Git change contains the renderer, documentation and video receipt; the MP4 remains a local deliverable.
