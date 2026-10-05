# 래브라도 쓰다듬기 인계 / Labrador petting handoff

후속 걷기·달리기는 [별도 제작 기록](LABRADOR_LOCOMOTION_20261005.md)에 있습니다. 이 문서는 기존 쓰다듬기 두 care 클립의 인수 기록이며 원본·제작본·기능은 보존합니다. / Later Walk/Run work is recorded separately; this document retains the original care delivery and its evidence.

2026-10-05. 최종 제작 범위는 **손 모델 없이, 자연스럽게 서 있는 래브라도의 머리를 마우스로 쓰다듬기**입니다. 실제 다운로드 모델의 53관절 리그와 원본 형상을 유지한 생산본, 두 모션, Unity prefab·입 소켓·표정·털 마스크를 만들었습니다. Unity 가져오기와 평가된 포즈 검사는 통과했습니다. 실제 Mac 실행본의 F2 조작 검사 22개도 통과했습니다. 플레이용 앱·미리보기·공개 코드 상태는 아래에 기록합니다.

The final scope is **mouse-driven head petting on a naturally standing Labrador, without hand models**. Production retains the acquired model's 53-joint rig and geometry, with two clips, a Unity prefab, mouth socket, eyelid shape and coat mask. Actual Unity import and evaluated-pose checks passed. Twenty-two actual native Mac/F2 checks also passed. Playable-app, preview and public-code status are recorded below.

## 확정 범위 / Confirmed scope

머리 피부에 닿은 드래그 위치와 방향을 고개·목 기울이기, 양쪽 귀의 부드러운 접힘, 원본 `target_1` 눈 감기 및 짧은 털의 국소 표면 반응에 연결합니다. [Family Time 공식 Headpats 개발 기록](https://sgthale.itch.io/family-time/devlog/1687521/family-time-devblog-7326-headpats-and-water)은 사용자가 요청한 반응의 참고 자료입니다. 실제 반응 구현은 `LabradorPetting.cs`, `WorkshopPetting.cs`, `LabradorPetting.shader`에 있습니다.

Skin contact and stroke direction drive head/neck lean, soft asymmetric ear folding, the original `target_1` eyelid shape and small local short-coat surface motion. The official Family Time headpat post is the reference for the requested response. Runtime implementation lives in those three files.

| 최종 모션 / Final clip | 길이 / Duration | 제작 내용 / Content |
| --- | --- | --- |
| `IdleFriendly` | 10.4333초 / seconds | kenchoo 원본 대기, 반복 연결 보정 / Original kenchoo idle with loop continuity correction |
| `PetEnjoy` | 4초 / seconds | 원래 서 있는 자세, 0.2° 호흡·약한 꼬리 움직임 / Original standing stance, 0.2° breathing and subtle distal tail wag |

두 모션은 반복합니다. `PetEnjoy`는 귀·머리를 자동으로 크게 움직이지 않아 입력 반응을 얹을 수 있습니다. 원본 눈 감기 morph는 보존하고 자동 모션을 제거했습니다. 앉기 탐색본은 `production/SeatedExploration/`에 보존하되 최종 manifest·FBX·GLB에는 포함하지 않습니다.

Both clips loop. The calm petting base leaves ears/head available for input overlays; the original eyelid morph is preserved and controlled by the runtime. Sitting exploration is retained separately and excluded from the final bundle.

이전 `LabradorCompanion`의 공격·탐색·아이템 회수·급식 코드와 16클립 계획은 **준비 자료**입니다. 해당 동행 기능은 이번 게임에 설치·연결된 완료 기능으로 보고하지 않습니다. 이번 최종 prefab의 필수 모션은 위 두 개입니다.

Earlier combat, search, retrieval and feeding modules and the sixteen-clip plan remain **prepared work**. Those companion features are not installed game features in this delivery. The final care prefab requires the two clips above.

## 출처와 변경 / Attribution and modifications

- 모델 / Model: [Labrador Dog — kenchoo](https://sketchfab.com/3d-models/labrador-dog-1f56cfbab07e4fe49b5d9e521c82073a), 원작 / original [Dog — all of life](https://skfb.ly/oHLVz), [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). 사용자가 받은 공식 converted 2k GLB는 19,312,512B이며 SHA256은 `0e30a09051903e2327c31371dc3dd973ca9da9c07a1c8aea5ca5f1af5bcda4fc`입니다. / The official user-downloaded source is preserved with that exact hash.
- 생산본 변경 / Production changes: 형상은 그대로 유지하고, 확인된 잘못된 뒷발톱·치아 가중치 8개 섬의 796정점만 교정했습니다. 미터 크기·입 소켓·두 반복 모션·머리털 마스크를 추가했습니다. 원본 2K 텍스처와 눈 morph를 유지하며 원본 GLB는 수정하지 않았습니다. / Geometry is unchanged; only 796 audited claw/tooth weights were repaired. Metre scale, attachment socket, two loops and a crown/ear coat mask were added; original textures, eyelid shapes and source GLB are preserved.
- 연구용 캡처 / Research captures: [Lifelike Agility and Play dataset — Lei Han 외 / et al.](https://springernature.figshare.com/articles/dataset/Lifelike_Agility_and_Play_in_Quadrupedal_Robots_using_Reinforcement_Learning_and_Generative_Pre-trained_Models/24968946), DOI `10.6084/m9.figshare.24968946.v1`, CC BY 4.0. 공식 ZIP 73,545,752B의 MD5 `746d592726eb7411f084518bfa1f3791`과 추출 BVH 33개 해시를 확인했습니다. 전체 제작자 이름은 `source-manifest.json`에 보존합니다. 이 캡처는 후속 모션 연구 자료이며 이번 두 최종 모션을 캡처 리타깃 결과로 표기하지 않습니다. / Archive and extracted-source hashes were verified; full author attribution is retained. These captures remain research material, not the source of the final two care clips.

## 보존 파일과 적용 위치 / Preserved files and integration

제작 자료의 기준 폴더는 `asset-staging/labrador-pet-20261005/`입니다. 원본·생산본·최종 사용자 자료를 보존하고 검토가 끝난 검증 캡처·로그·중간 백업은 요약 후 정리합니다.

The staging folder is the local production archive. Preserve sources, production and final user artifacts; reviewed validation captures/logs and intermediate backups may be cleaned after retaining summaries.

| 위치 / Location | 용도 / Purpose |
| --- | --- |
| `source/LabradorDog_kenchoo_2k.glb`, `source/raw_bvh_data.zip`, `source/raw_bvh_data/` | 모델·캡처 원본 및 공식 메타데이터 / Original model, captures and official metadata |
| `production/LabradorPet_Animations.blend` | 텍스처를 포함한 최종 Blender 제작본 / Final Blender production with packed textures |
| `export/LabradorPet_Model.fbx`, `export/Animations/{IdleFriendly,PetEnjoy}.fbx`, `export/Textures/`, `export/animation-manifest.json` | Unity 가져오기 묶음 / Unity import bundle |
| `export/LabradorPet_Petting.glb` | 두 모션·눈 morph·털 마스크가 포함된 상호작용 미리보기 모델 / Interactive-preview model with two tracks, eyelid morph and coat mask |
| `export/LabradorPet_Poster.png`, `export/LabradorPet_Petting.png`, `export/LabradorPet_Motions.mp4` | Blender 포스터·평가된 Unity 반응 이미지·최종 초 이동 가능 영상 / Blender poster, evaluated Unity reaction image and final seekable reel |
| `production-summary.json`, `animation-validation.json`, `unity-import-summary.json`, `unity-render-summary.json`, `video-seek-verification.json` | 파일 해시와 작은 검증 근거 / File hashes and compact validation evidence |

Unity 적용 파일은 `unity-game/Assets/RPG/Resources/Pets/Labrador/PetModel.prefab`, `Animations/{IdleFriendly,PetEnjoy}.anim`, `Models/`, `Textures/`, `Labrador.mat`입니다. `unity-game/Assets/RPG/Gameplay/Pets/LabradorPetting.cs`가 입력 반응을 맡고 `unity-game/Assets/RPG/Shaders/LabradorPetting.shader`가 털 마스크를 사용합니다. Unity/glTF 좌표는 미터, +Z 앞, Y 위입니다. `MouthSocket`은 `Head_1` 아래에 있으며 월드 크기는 1입니다.

Those Unity assets are imported into the main project. Input overlays and the masked coat shader use the actual rig. Unity/glTF coordinates are metres, +Z forward and Y up; the head-parented mouth socket has world scale one.

리그의 0.3 균일 크기는 의도된 설정입니다. 실제 피부 접촉 좌표는 `BakeMesh(true)`로 평가합니다. `Head_1`과 윗입 보조 관절 `Neck3.001_11`은 형제 관절이므로 같은 머리 회전을 받아야 하며, 그 아래 `Neck3.002_10`이 아랫턱입니다. 모든 원본 UV 집합은 동일하고 원본 재질은 normalScale 0.2·metallicFactor 0.0909091입니다. Unity의 normal/tangent 셰이딩에서 몸통 경계가 보여 실제 비교 검사 후 설치본의 normal 강도는 0으로 설정했습니다. 원본 normal 텍스처·Blender/GLB 강도 0.2는 보존하며 색상 텍스처의 털 디테일과 국소 쓰다듬기 반응은 유지합니다.

Keep the intentional 0.3 rig scale and evaluate skin contact with `BakeMesh(true)`. Head and upper-mouth helper are siblings and must receive the same head delta; the helper's child is the lower jaw. Source UV sets are identical. Unity normal/tangent shading introduced torso seams, so the installed material uses normal strength zero after comparison checks. The original normal texture and Blender/GLB strength 0.2 are preserved, along with albedo coat detail and local petting deformation.

## 완료한 검사 / Completed checks

- Blender 5.2.1 LTS: **24개 검사·435개 실제 변형 피부 프레임 통과**. 발 지지·반복 위치/속도·유한 값·원본 형상 및 GLB 해시·가중치 교정·눈의 털 마스크 제외·입 소켓을 확인했습니다. `PetEnjoy`의 최대 발 중심 이동은 0.039mm입니다. / Twenty-four checks and 435 evaluated-skin frames passed; maximum paw-centroid drift in the care loop is 0.039mm.
- FBX 재수입: **두 클립에서 총 6프레임**을 생산본과 대조했습니다. 최대 피부 좌표 차이는 `6.991e-7 m`입니다. GLB는 각 트랙 0초 시작과 manifest 길이를 확인했습니다. / Six delivered-FBX samples match production; GLB track timing matches the manifest.
- 영상: **960×640, 24FPS, H264, 18.417초**. MP4 인덱스를 앞에 배치했고 AVFoundation으로 5구간을 이동해 시간 오차 0초를 확인했습니다. 영상은 두 기본 모션을 보여주며 실제 마우스 반응은 상호작용 미리보기에서 확인합니다. / The final reel passed five exact seeks; runtime mouse reactions are shown in the interactive preview.
- Unity 6000.3.25f1 실제 가져오기: **56개 통과**. 실제 prefab, 리그·입 소켓·두 클립 바인딩·포즈 샘플과 반복 경계를 확인했습니다. / Fifty-six actual-asset import checks passed.
- Unity 평가 포즈 렌더: **33개 통과**. `BakeMesh(true)`로 실제 피부·눈 morph를 평가하고 재질·털 마스크·귀 접힘을 검사했습니다. 이 근거는 격리 PreviewScene 렌더이며 실제 앱 화면 인수와 구분합니다. / Thirty-three evaluated-pose/render checks passed in a PreviewScene; this is separate from live-app acceptance.
- PlayMode fixture: **28개 통과**(쓰다듬기 12개·준비된 동행 코드 7개·거래 보존 9개). 입력·접촉·상태 검사는 시험 fixture 근거이며 실제 모델 검사는 위 가져오기·렌더 근거로 남깁니다. / Twenty-eight fixture checks passed (12 petting, 7 prepared companion and 9 transaction checks); actual-model evidence is recorded separately above.

후속 리타깃을 위한 원본 디코더 검사도 보존합니다. 독립 BVH FK와 Blender importer를 3캡처·9프레임·549관절 좌표로 비교해 최대 차이 `1.7707e-6 m`로 통과했습니다. 두 hierarchy 변형을 구별해야 하며 관련 재사용 도구는 `tools/dcc/labrador_pet_*.py`에 있습니다.

Source decoder evidence remains useful for future retargeting: 549 joint-position comparisons across three captures and nine frames passed with maximum error `1.7707e-6 m`. Preserve the hierarchy-variant distinction and reusable DCC tools.

## 실행본 인수 상태 / Native acceptance status

- 최종 PlayMode 검사 / Final PlayMode checks: **28/28 통과 / passed**, 실패·건너뛰기 0. 검사한 18개 파일의 SHA256은 최종 소스와 일치합니다. / All eighteen tested-file hashes match the final sources.
- Mac 실행본 빌드 / Native Mac build: **통과 / passed**. Unity 6000.3.25f1, 오류 0개·경고 171개(프로젝트 기존 경고 포함), 약 3.29GB. 최종 펫 셰이더의 가져오기·렌더 오류는 0개입니다. / The final native game built with zero errors; existing project warnings remain.
- 실제 F2 쓰다듬기 조작 / Actual native F2 care flow: **22개 통과 / passed**. 실제 모델의 피부 ray, 정지 커서, 이동·놓기, 귀·눈·털 반응, 손 숨기기, F2 정지·재개·재시도·원래 월드/가방 복귀를 확인했습니다. 물리적인 데스크톱 키·마우스 포커스·소리는 자동 검사 범위 밖입니다. / Deterministic actual-app screen rays verify contact, reactions, no hands, pause/resume/retry and world/inventory restoration; physical desktop input and audible output are outside this check.

상호작용 미리보기는 `python3 tools/labrador-petting-viewer/server.py`로 실행하여 http://127.0.0.1:8773/ 을 엽니다. 실제 브라우저에서 머리 드래그·귀/눈 반응·전체 보기·다시 시작을 확인했고 콘솔 오류·경고는 0개였습니다. 왼쪽 버튼을 누르고 머리를 천천히 움직입니다. 본편은 F2 → 래브라도 쓰다듬기이며, E/Esc로 가까운 시점을 끝냅니다.

Run the local interactive preview with the command above. Actual browser drags, ear/eye reactions, full view and reset were reviewed with no console errors or warnings. Hold the left mouse button and move slowly over the head. The native game uses F2 → Labrador petting; E/Esc leaves the close view.

최종 실행본 설치·공개 코드·정리 결과는 `petting-summary.json`과 `cleanup-summary.json`에 기록합니다. 원본·생산본·최종 모델/영상/포스터·최신 플레이용 앱·Dock/Applications 연결·이전 셰퍼드 제작 원본은 보존합니다. 공개 체크포인트에는 이 작업의 코드·재사용 제작 도구·검증 요약만 포함하고 라이선스 에셋 바이너리는 로컬에 보존합니다.

Installation, publication and cleanup are recorded in the compact summaries. Preserve the acquired sources, final production/model/video/posters, latest playable app and launch links, and previous Shepherd production originals. The public checkpoint contains this task's code, reusable production tools and summaries; licensed asset binaries remain local.

최종 플레이용 앱은 `unity-game/Builds/MusimusihanRPG.app`에 설치하고 deep/strict 서명·최종 DLL 해시·기존 Applications/Dock 경로를 확인했습니다. 한국어 표시 이름은 유지하고 서명용 실행 파일 이름만 ASCII로 정규화했습니다. 정리한 작업 자료의 할당량은 9.91GB, 현재 디스크 여유 공간은 19.73GB입니다. APFS 공유 블록과 다른 진행 중 작업 때문에 할당량과 실제 공간 변화는 다릅니다.

The latest playable app is installed at the canonical path with its deep/strict signature, final assembly hashes and existing launch links verified. Its Korean display name remains; only the internal executable filename was normalized to ASCII for the resource seal ([Apple guidance](https://developer.apple.com/forums/thread/706379)). Removed task allocation totals 9.91GB; current free space is 19.73GB. APFS sharing and concurrent work mean allocation differs from recovered space.

작업 코드 97개 파일의 GitHub 커밋 `fa132e7997b3ef1f162d0c647ad464e8e22a01cb`을 원격에서 확인하고 로컬 작업 브랜치와 일치시켰습니다. / Verified all 97 task files and the remote code commit against the local task branch.
