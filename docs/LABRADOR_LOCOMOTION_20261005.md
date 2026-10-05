# 래브라도 걷기·달리기 / Labrador Walk and Run

같은 kenchoo 래브라도에 두 순환 모션을 추가했습니다. 기존 모델·원본·쓰다듬기 제작본과 두 care 모션은 보존합니다. 실제 개 캡처의 몸통·고개·발 디딤 순서를 사용하고, 발 고정/들기 경로와 해부학적 다리 IK를 래브라도 체형에 맞췄습니다. 발 경로 전체를 원본에서 그대로 복사한 모션은 아닙니다.

Two gait loops are added to the same kenchoo Labrador. Original model, production and care clips are preserved. Captured canine body/head motion and footfall timing are combined with proportion-fitted planted/swing paw paths and anatomical limb IK; the paw paths are fitted rather than a literal capture copy.

| 모션 / Clip | 순환 / Cycle | 기준 속도 / Nominal speed | 동작 / Gait |
| --- | --- | --- | --- |
| `Walk` | 0.766667초 / s, 60FPS | 0.715115m/s | 네 발의 순차 접촉 / Four-beat walk |
| `Run` | 0.4초 / s, 60FPS | 2.314164m/s | 비대칭 접촉·짧은 공중 구간 / Asymmetric fast gait with brief flight |

두 클립의 루트는 제자리이며 몸통의 세로 움직임은 유지합니다. 실제 이동에 연결할 때는 위 속도를 기준으로 사용합니다. 이번 범위는 모션과 모션 시연이며 동행 AI·경사면 보행·충돌·공격 행동은 포함하지 않습니다.

Both game clips keep the root in place while retaining body vertical motion. Use their nominal speeds when driving translation. This delivery covers animation and its demonstration, not companion AI, slope handling, collisions or combat.

## 보기와 조작 / Preview and controls

- 로컬 미리보기 / Local viewer: `python3 tools/labrador-petting-viewer/server.py`, http://127.0.0.1:8773/locomotion/ . 걷기/달리기, 옆/비스듬한 시점, 정지·시간 이동을 제공합니다. 바닥 격자는 기준 속도로 움직이며 제자리 보기로 전환할 수 있습니다. / Choose a gait/view, pause or seek; ground movement matches nominal speed and can be disabled.
- 본편 / Native game: **F2 → 래브라도 · 걷기 / 달리기 모션**. **1/2 키 또는 화면 버튼**, **E/Esc 시점 나가기**, 기존 F2 정지·재시도·원정 복원을 사용합니다. 모션 시점 중 손·장비·단축 슬롯 입력을 숨기고 원래 설정을 복원합니다. / Keys/buttons select the actual clips; existing trial isolation, pause/retry and restoration are reused.
- `export/LabradorPet_Locomotion.mp4`: **12초, 960×640, 24FPS, H264**, 걷기/달리기를 각각 옆·비스듬한 시점에서 보여줍니다. MP4 인덱스는 앞에 있고 AVFoundation 5구간 시간 이동의 오차는 0초입니다. / The seekable reel shows both actual loops and views; five seeks are exact.

## 제작·게임 적용 / Production and integration

기준 폴더 / Base: `asset-staging/labrador-pet-20261005/`.

- `production/LabradorPet_Locomotion.blend`: 새 최종 Blender 제작본 / New final production.
- `export/Locomotion/{Walk,Run}.fbx`: Unity용 두 클립 / Two Unity clip exports.
- `export/LabradorPet_Locomotion.glb`: 원래 care 두 개와 새 gait 두 개, 눈 morph·털 마스크를 포함한 별도 미리보기 / Separate four-clip preview with original morph/mask.
- `export/locomotion-manifest.json`: 길이·속도·출처·좌표 기준 / Timing, speed, source and coordinates.
- `export/LabradorPet_{Walk,Run}.png`, `export/LabradorPet_Locomotion.mp4`: 최종 포스터와 영상 / Final posters and video.
- `unity-game/Assets/RPG/Resources/Pets/Labrador/Animations/{Walk,Run}.anim`: 실제 설치한 모션 / Installed resources.
- `LabradorLocomotionDemo.cs`, `WorkshopPetting.cs`: 실제 F2 모션 시연 / Actual F2 demo.
- `tools/dcc/labrador_pet_locomotion*.py`, `LabradorLocomotionInstaller.cs`: 재사용 제작·평가·임포트·영상 도구 / Reusable authoring, review, import and reel tools.

## 검증 근거 / Validation evidence

- `locomotion-animation-validation.json`: **27개 통과**, 120Hz 평가 피부 142프레임·FBX 왕복 6샘플. 메시·53개 본 rest matrix·스킨 가중치·눈 morph·털 마스크·기존 care 액션 동일. 최대 FBX 피부 차이 0.000970mm. 전체 피부의 바닥 침범은 3mm 허용치 안입니다. / All production checks passed; rest assets and prior care actions match exactly.
- `locomotion-independent-review.json`: **13개 기준 통과**, 142자세·232개 지지 발 샘플·실제 피부 렌더 9장. 관절 뒤집힘을 수정했습니다. 기준 속도로 움직였을 때 지지 발바닥 피부의 잔여 이동은 최대 **2.589mm**, 바닥 높이는 **−0.444~+0.150mm**입니다. 평지와 샘플 피부 중심 기준이며 실제 압력·충돌·경사면은 검사하지 않습니다. / Independent anatomy/contact/visual review passed with small bounded sole drift; no claim of absolute zero skating or physical force measurement.
- `locomotion-unity-import.json`: **102개 통과**. 실제 FBX와 설치 clip 각 593곡선, Walk 48·Run 25 포즈 샘플, 반복 경계·루트 바닥 방향 이동 0. 기존 모델·재질·텍스처·prefab·care 에셋 11개는 동일합니다. / Actual imported clips bind and loop correctly; prior assets remain byte-identical.
- `locomotion-playmode-validation.json`: **32/32 통과**(기존 28개 + 새 모션 시점/시계/상태 검사 4개). 검사 소스 해시와 최종 파일이 일치합니다. / Four new lifecycle fixtures pass alongside prior regression checks; tested hashes match final sources.
- `locomotion-native-acceptance.json`: **30/30 통과**. 실제 Mac 실행본에서 F2 등록·진입, 실제 스킨 모션 전환, 손·장비 숨김, 정지·복귀·재시도·초기화, 기존 쓰다듬기와 원래 가방·게임 상태 복원을 확인했습니다. 검사 시점은 실제 렌더링 직전 보정 순서에 맞췄습니다. / Thirty checks pass in the actual Mac player, including gait switching, late-frame visibility, trial lifecycle, prior petting and original state restoration.

실제 Mac 빌드·F2 인수·설치·원격 반영·정리 결과는 `locomotion-summary.json`과 관련 작은 요약에서 최종 상태를 기록합니다. 네이티브 검사는 결정적 모드 명령을 사용하며 물리적 데스크톱 키·마우스 포커스·소리는 별도 범위입니다.

Final native build/F2 acceptance, installation, publication and cleanup are recorded in the compact summary. Native automation uses the production mode command; physical desktop keys, focus and audible sound are outside those checks.

## 출처와 보존 / Attribution and preservation

모델: [Labrador Dog — kenchoo](https://sketchfab.com/3d-models/labrador-dog-1f56cfbab07e4fe49b5d9e521c82073a), 원작 [Dog — all of life](https://skfb.ly/oHLVz), CC BY 4.0. 원본 SHA256 `0e30a09051903e2327c31371dc3dd973ca9da9c07a1c8aea5ca5f1af5bcda4fc`는 유지합니다.

모션: Lei Han 외, [Lifelike Agility and Play dataset](https://doi.org/10.6084/m9.figshare.24968946.v1), CC BY 4.0. `dog_quad_walk_002.bvh`와 `dog_fast_run_02_006.bvh`의 선택 구간을 사용했습니다. 전체 제작자·출처·라이선스·변경 사항은 `source-manifest.json`, 제작 요약과 실행본의 `StreamingAssets/ThirdPartyNotices/Labrador.txt`에 기록합니다.

Model and captured-motion attribution is preserved, including modifications and the original source hash. Licensed binaries stay local under the Unity project rules; task code, reusable tools and compact receipts are published. Source/capture archives, both final Blender productions, care/gait exports, final video/posters and latest playable app are retained. Reviewed task-only QA, logs and superseded builds are cleaned after recording results.
