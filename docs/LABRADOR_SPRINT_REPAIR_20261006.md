# 래브라도 앞다리 피부 변형 수정 / Labrador foreleg deformation repair

사용자가 기존 Sprint의 0.63/0.70초 자세에서 다리가 뒤틀리고 가슴에 파묻힌다고 지적했고, 진단 후 수정을 요청했습니다. [기존 진단](LABRADOR_SPRINT_20261006.md)에서 상완의 과한 뒤·위 회전과 비인접 앞다리–몸통 표면 교차를 확인했습니다. 이전 수치/시각검사를 새 수정의 인수 근거로 재사용하지 않습니다.

The user reported malformed forelegs embedded in the chest and authorized a repair. The prior diagnosis confirms excessive upward/backward humerus rotation and nonadjacent foreleg–torso surface intersection. Prior numerical/visual acceptance does not establish this repair's quality.

원본·기존 제작본은 보존하고 `asset-staging/labrador-sprint-repair-20261006/`에 별도 제작·출력을 저장합니다. 기본 .70초·60fps의 질주 리듬을 유지하되 회수 손목목표, 견갑 위치와 상완 방향을 함께 조정합니다. 머리·몸통·귀·꼬리 움직임과 앞뒤로 뻗기/배 아래 회수 흐름은 피부 형태 제약 안에서 조율합니다. acquired mesh/rest/weights/morph/coat와 care/Walk 키는 보존합니다.

Original and rejected productions remain preserved; repair output is separate. Wrist recovery, scapular position and humerus orientation are coordinated within actual skin-shape limits, retaining the .70s/60fps rhythm and extension/collection flow. Acquired mesh/rest/weights/morph/coat and care/Walk keys remain unchanged.

새 인수는 같은 원본 영역 마스크의 비인접 앞다리–몸통 실제 표면 교차, 어깨 형태/삼각형면적압축, 상완방향, 전주기 피부·접지·코어·반복 경계, 최종 WebGL·Unity·Mac실행본을 확인합니다. 선택 표면 검사 수치는 전체mesh 충돌량·침범깊이·미적 사용자승인을 뜻하지 않습니다.

Acceptance checks the same source-defined surface regions for nonadjacent foreleg–torso crossing, shoulder shape/triangle-area collapse and humerus orientation alongside skin/support/core/seam, final WebGL/Unity and a fresh native player. Selected-surface counts are not all-mesh collision volume/depth or aesthetic user approval.

수정 완료: 어깨와 손목 회수 경로를 함께 조정해 팔꿈치가 가슴 위로 올라가던 자세를 없앴습니다. 원래 짧은 상완 길이에 맞춰 회수 높이·전개 시점·견갑 이동 범위를 조정했고, Run 동안 양쪽 어깨와 손목을 함께 바깥으로 3mm 옮겨 남아 있던 작은 가슴 표면 교차를 해소했습니다. 상대 다리 자세·주기·몸통 진행을 유지합니다. 피부 마스크·가중치·메시를 바꿔 검사 범위를 줄이지 않았습니다.

Completed: coordinated shoulder and wrist recovery prevents the former elevated elbow/embedded forearm. Recovery height, unfolding timing and scapular glide fit the original short upper arm. A constant3mm outward shift of both fore shoulders and wrists resolves the remaining small sternum crossing while preserving relative limb pose and body progression. Mesh, weights and original surface masks were not altered to narrow acceptance.

| 최종 검증 / Final check | 결과 / Result |
|---|---|
| 제작 기본 검사 / Authoring | 31/31 통과 / passed |
| 고정 피부 영역 / Fixed original skin regions | Blender86 + 실제 GLB86자세, exact/coplanar 교차0 / zero sampled crossing |
| 피부·접지·몸통 / Skin, contact, core | 169샘플; 원래 몸통·머리 키와169샘플 진행 동일 / original core preserved |
| 최종 형태·시간 진행 / Final shape and progression | root10자세+3근접, 실제 영상90프레임/8시트 / reviewed |
| 영상 구간 이동 / Video seeking | AVFoundation5 exact seeks 통과 / passed |
| 실제 브라우저 / Actual browser | Run12자세, Walk, 배속·시점·정지·탐색·재생·바닥 전환; console 경고/오류0 / passed |
| Unity Run 교체 / Actual import | 195/195 통과,593curves,86피부샘플 / passed |
| 새 Mac 실행본 / Fresh native player | 실제 F2 30/30 통과; 서명·설치·실행 연결 확인 / passed |

Unity는 Run.fbx와 Run.anim만 교체했습니다. 두 importer metadata와 GUID를 포함한 나머지31 resource/meta, 런타임3파일은 byte-identical입니다. 기존 쓰다듬기 F2·PetEnjoy·가방·원정 상태를 보존하고, 걷기/달리기·정지/재개·retry/reset을 새 실행본에서 확인했습니다. 빌드는 오류0, 기존 shader/compiler 등에 대한 경고176개이며 Labrador 관련 경고0입니다. 경고 분류는 별도 receipt로 남겼습니다.

Only Run.fbx/Run.anim changed in Unity; the other31 resource/meta files, GUIDs and3 runtime files remain unchanged. The fresh app passed30 actual F2 checks covering locomotion, existing PetEnjoy, pause/resume, retry/reset and original world/inventory state. Build: zero errors,176 reviewed shader/compiler and other warnings, zero Labrador-specific warnings.

한계: 원래 스킨의 작은 관절 주름은 남습니다. 왼앞발 sole-centroid 이동 최대5.38mm, Blender 중간 피부 최저−0.787mm는 기존3mm 바닥 허용 범위 안이며, authored key 발바닥+0.6mm와 구분합니다. 실제 GLB 중간 샘플은 Blender BEZIER와 export LINEAR 차이로 최대10.448mm 위치 차이가 있으나 그 출력 자체의86자세 표면 교차도0입니다. 반복 경계 finite-epsilon 속도 차이는 ε를 줄이면0으로 수렴하며 C1 불연속으로 판정하지 않았습니다. 힘/압력중심·전체mesh 무충돌·사용자의 미적 승인을 측정한 결과는 아닙니다.

Limits: original joint skin folds remain. LF sole-centroid drift reaches5.38mm; intermediate Blender skin minimum−0.787mm is inside the existing3mm tolerance and differs from authored-key pad clearance+0.6mm. Actual glTF interpolation differs from Blender BEZIER by up to10.448mm between keys, but its own86 sampled surface checks are clear. Finite-epsilon loop-velocity differences converge toward zero as epsilon decreases; no C1 discontinuity is established. These checks do not measure force, pressure centre, all-mesh collision freedom or user aesthetic approval.

최종 산출물은 `asset-staging/labrador-sprint-repair-20261006/`의 `production/LabradorPet_SprintRepair.blend`, `export/LabradorPet_SprintRepair.glb`, `export/Locomotion/Run.fbx`, `export/sprint-repair-manifest.json`, `export/LabradorPet_SprintRepair.mp4`와 Extended/Collected 포스터입니다. 12초 영상은 정상 옆모습·반속도 옆모습·정상 비스듬한 시점을 각각4초 담습니다. .70초/60fps, 기준2.3472118787m/s입니다. 최종 실제 앱은 `unity-game/Builds/MusimusihanRPG.app`이며 Applications의 `무시무시한 RPG.app` 연결과 Dock을 보존했습니다. [직접 조작](http://127.0.0.1:8773/locomotion/)은 수정된 GLB를 사용합니다. 원본·이전 제작본·care/Walk와 licensed binaries는 로컬에 보존합니다.

Final production, exported model/Run, manifest,12s reel and two posters remain in the repair staging folder. The reel contains4s each of normal side, half-speed side and normal quarter view. Final playable remains `unity-game/Builds/MusimusihanRPG.app`, preserving Applications/Dock links. The local viewer selects the corrected GLB. Original assets, prior productions and licensed binaries remain local.

작은 인계 요약은 `repair-summary.json`, 제작/독립 인수는 `sprint-repair-production-summary.json`와 `sprint-repair-independent-acceptance.json`, 실제 실행은 `repair-native-acceptance.json`·`repair-native-install.json`, root 형태 검토는 `repair-root-visual-review.json`에 있습니다. 원본 마스크 SHA·측정·한계·최종 파일 SHA를 함께 남겨 Chat On Steroids에서도 같은 프로젝트 파일을 이어 쓸 수 있습니다.

Compact handoff, source hashes, fixed-mask signatures and limitations are retained in the summary/production/independent/native/root receipts for continued work through the existing project files.

정리 완료: 제작·독립·root 담당자가 자기 검토 자료만 정리했고, 합산 제거 할당량은 3,414,728,704바이트(약3.41GB)입니다. root 정리 전후 실제 여유 증가 관측은 3,308,990,464바이트이며, 현재 여유 공간은 13,253,750,784바이트(약13.25GB)입니다. APFS 공유 블록과 다른 작업 때문에 할당량과 확보 공간을 구분합니다. 현재 플레이 앱·Applications/Dock·원본·최종 제작본·영상/포스터·재사용 도구·importer metadata·사용 중인 Editor log/Library는 보존했습니다.

Cleanup completed by each contributor within owned validation scope. Combined removed allocation: 3,414,728,704bytes (~3.41GB); root observed free-space increase: 3,308,990,464bytes. Current free space: 13,253,750,784bytes (~13.25GB). APFS sharing and concurrent work limit direct allocation/recovery comparison. Final media, source production, playable/launch links and active Editor resources remain preserved.

공개 저장소의 기존 `codex/labrador-pet-20261005` 작업 브랜치에 이번 코드·문서·작은 검증 기록만 반영합니다. licensed 모델/FBX/영상/app과 인증 정보·검증 캡처는 업로드하지 않습니다. 커밋과 원격/로컬 일치 확인은 publication receipt에 남깁니다.

Only this repair's code, documentation and compact evidence are published on the existing Labrador task branch. Licensed model/FBX/movie/app and temporary captures remain local. The publication receipt records commit and remote/local verification.
