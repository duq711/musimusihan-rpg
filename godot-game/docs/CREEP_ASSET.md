# 크리프 에셋 설치 / Creep asset installation

## 출처와 공개 저장소 / Source and public repository

모델은 **andriichykrii**의 [Creep Creature](https://www.cgtrader.com/free-3d-models/character/fantasy-character/creep-creature)입니다. 상품 페이지의 라이선스 표시는 **Royalty Free License (no AI)**입니다. [CGTrader 이용 조건 21A·21B](https://www.cgtrader.com/pages/terms-and-conditions)는 독립 에셋 재배포를 제한하므로, 다운로드한 FBX·텍스처와 변환한 GLB는 공개 GitHub에 올리지 않습니다. 공개 저장소에는 변환 코드·게임 연결·검사·이 설치 안내를 제공합니다. 각 사용자는 원본 페이지에서 에셋을 받아 로컬에 설치합니다.

The model is **Creep Creature by andriichykrii**, listed under **Royalty Free License (no AI)**. The linked CGTrader terms restrict standalone asset redistribution. Downloaded FBX/textures and the converted GLB therefore remain local. The public repository provides conversion code, integration, tests, and these instructions; each user obtains the asset from its source page.

원본은 프로젝트 루트의 `exports/Creep_20260917/source/`에 보존하고, 게임이 읽는 파일은 `godot-game/assets/licensed/creep/creep.glb`입니다. 두 경로는 Git에서 제외됩니다. 이 제외를 해제하거나 원본 다운로드 주소의 인증 정보·임시 토큰을 커밋하지 않습니다.

Original files are preserved under `exports/Creep_20260917/source/`; the game loads `godot-game/assets/licensed/creep/creep.glb`. Both directories are ignored by Git. Keep the asset files and authenticated download details out of commits.

## Mac에서 설치 / Install on Mac

CGTrader에서 전체 품질 모델 **Creep.fbx**와 기본 스킨 텍스처 묶음 **tex.rar**를 받습니다. 프로젝트 루트에서 아래 명령을 실행하되 두 입력 경로를 실제 다운로드 위치로 바꿉니다. 변환기는 Blender 안에서 실행되므로 일반 Python으로 실행하지 않습니다.

Download the full-quality **Creep.fbx** and the base-skin **tex.rar** package. From the repository root, replace the two input paths below with their actual locations. Run the converter inside Blender, not ordinary Python.

```sh
/Applications/Blender.app/Contents/MacOS/Blender \
  --background --factory-startup --disable-autoexec \
  --python tools/build_creep_asset.py -- \
  --fbx "/path/to/Creep.fbx" \
  --textures "/path/to/tex.rar"
```

이 Mac에 보존된 원본으로 다시 만들 때는 두 인자를 각각 `exports/Creep_20260917/source/Creep.fbx`, `exports/Creep_20260917/source/tex.rar`로 지정합니다. 같은 보존 경로에 다른 원본이 있으면 변환기가 덮어쓰기를 거절합니다. 다른 원본 세트는 `--staging`으로 별도 폴더를 지정합니다.

To rebuild from the originals preserved on this Mac, use those two paths under `exports/Creep_20260917/source/`. The converter refuses to overwrite a preserved source with different content; use a separate `--staging` directory for a different source set.

기본 출력은 게임이 읽는 `creep.glb`이며, 제작 사본에서 키를 1.95m로 맞추고 바닥·정면 방향을 정리합니다. 텍스처는 최대 2048px로 줄여 색·노멀·거칠기·금속도·차폐 채널을 GLB에 포함합니다. 원본 17개 애니메이션과 뼈대를 유지하며, 게임용 스킨은 정점당 최대 8개 뼈의 영향을 사용합니다. 원본 파일은 바꾸지 않습니다. 출력 해시·크기·클립 목록·변환 설정은 로컬 `exports/Creep_20260917/build_manifest.json`에 남습니다.

The default output is the game's `creep.glb`. A working copy is normalized to 1.95m, grounded and oriented forward, with embedded PBR textures capped at 2048px. All 17 source clips and the rig are retained; the runtime skin supports up to eight bone influences per vertex. Source files remain unchanged. The local build manifest records hashes, dimensions, clips, and conversion settings.

출력 후 Godot가 새 GLB를 가져오게 프로젝트를 다시 불러옵니다. 이 Mac에서는 프로젝트 루트에서 다음 백그라운드 명령을 사용할 수 있습니다. / Reload the project so Godot imports the new GLB. On this Mac, this can be done in the background from the repository root:

```sh
/Users/duq711gmail.com/Desktop/Godot.app/Contents/MacOS/Godot \
  --headless --path godot-game --editor --quit
```

## 게임 연결 / Gameplay integration

집중 타격에 따른 팔다리·머리 절단은 [부위 절단 안내](CREEP_DISMEMBERMENT.md)를 따른다. 원본 설치 뒤 `python3 tools/build_creep_dismemberment.py`를 실행하면 별도 `creep_dismembered.glb`를 만든다. 원본을 보존하며, 파생 에셋 역시 로컬에만 둔다.

For concentrated-hit limb/head severance, follow the linked dismemberment guide. After installing the original, run `python3 tools/build_creep_dismemberment.py` to build the separate local-only `creep_dismembered.glb`.

테스트룸의 `F2 → 기본 → 크리프 · 괴물 근접 전투`는 실제 크리프 1명, 검·방패와 회복된 플레이어를 준비합니다. `LMB` 공격, `RMB` 방어, `F2` 메뉴 복귀를 사용합니다. 같은 항목을 다시 선택하면 적을 재생성하고 체력을 회복합니다. 초기화하면 기존 시험 적 두 명으로 복구하고, 시험 종료 시 원래 원정과 인벤토리를 복원합니다.

`F2 → 기본 → 크리프 · 괴물 근접 전투` starts a real Creep duel with a healed player and sword/shield. LMB attacks, RMB guards, and F2 returns to the menu. Reselecting heals and respawns the opponent; reset restores the two default trial enemies. Leaving restores the original expedition and inventory.

본편에서는 에셋이 설치된 경우에만 폐광 `store_guard` 한 자리가 크리프로 바뀝니다. 전체 적은 여섯 명이며 기존 창고 적의 수치·전투 피해 처리·보상·귀환문 조건을 유지합니다. 에셋이 없는 공개 저장소 복사본은 해당 자리에 기존 검지기를 생성합니다. 미설치 상태에서 F2 크리프 항목을 선택하면 설치 안내를 표시하고 메뉴와 기존 시험 대상을 유지합니다.

Only the mine's `store_guard` encounter changes when the asset is installed. Six enemies remain, using the existing store encounter stats, damage handling, rewards, and extraction rules. A clone without the asset spawns the original warden. Selecting the Creep trial without installation shows an installation notice and preserves the open menu and current actors.

| 게임 상태 / Game state | 사용 클립 / Runtime clip |
| --- | --- |
| 대기 / Idle | `idle` |
| 추적 / Chase | `walk` |
| 물기 / Bite | `bite` |
| 양손 연타 / Two-punch attack | `punch` |
| 피격·저스트 가드 경직 / Hit and parry reaction | `hit` |
| 사망 / Death | `hit` 0.18초 반응 → 실제 래그돌 / 0.18 s reaction → physics ragdoll |

GLB에는 나머지 11개 클립도 보존합니다: `idle_crouched`, `walk_calm`, `walk_crouched`, `eat`, `roar`, `sniff`, `spawn_jump`, `despawn_jump`, `sleep_start`, `sleep_loop`, `sleep_finish`. Godot 기본 가져오기는 `sleep_loop`를 `sleep`으로 바꾸고 반복 재생을 설정합니다. 현재 AI에서 이 추가 동작을 실행하는 기능은 연결하지 않았습니다.

The other eleven clips above remain in the GLB but are not connected to current AI behavior. Godot imports `sleep_loop` as the looping `sleep` clip.

원본 공격 클립에는 반복 동작이 들어 있습니다. 게임에서는 첫 번째 완결 동작만 이어서 사용합니다. 물기는 1.6초에 한 번 타격하고, 주먹은 1.2초 동안 두 번 타격하며 각 접촉은 설정 피해의 절반입니다. 공격은 두 종류를 번갈아 선택합니다. 가드·저스트 가드·피격·사망·보상은 기존 근접 전투 규칙에 연결합니다.

The source attack clips contain repeated actions; gameplay uses only their first complete cycle. Bite takes 1.6 seconds with one contact. Punch takes 1.2 seconds with two contacts, each delivering half the configured damage. Attacks alternate and use existing guard, parry, hit, death, and reward handling.

## 공격 후 추격 전환 / Attack-to-chase transition

2026-09-19 후속 수정은 서 있는 크리프의 물기·양손 연타가 끝난 뒤 걷기 자세로 갑자기 바뀌는 현상을 다룬다. 공격 끝의 실제 뼈 자세를 시작점으로 유지하고 **0.28초 동안 걷기 자세로 보간**한다. 걷기를 항상 첫 프레임에서 다시 시작하지 않고 현재 발 자세와 가까운 보행 구간을 고르며, 보행 진행을 실제 이동 속도에 맞춘다. 추격에서 공격 준비로 들어갈 때도 **0.12초** 동안 자세를 연결하며 기존 접촉 시점은 유지한다. 원본 모델과 17개 클립은 보존한다.

The 2026-09-19 follow-up addresses abrupt standing Creep transitions from bite/two-punch attacks into walking. It preserves the actual ending skeletal pose and **blends into walking over 0.28 seconds**. Instead of restarting at the first walk frame, it selects a phase whose foot pose is close to the current pose, then matches gait progress to actual movement speed. Chase-to-windup also blends over **0.12 seconds**, retaining existing contact timing. The source model and all seventeen clips remain intact.

`F2 → 기본 → 크리프 · 괴물 근접 전투`에서 물기와 양손 연타가 각각 끝날 때 `S`로 뒷걸음쳐 공격 거리 밖으로 나간다. 크리프가 추격을 재개할 때 발과 몸통이 이어지는 모습을 확인한다. 저스트 가드는 공격을 중단하므로 전환을 관찰할 차례에는 공격을 끝내게 한다. `F2`는 전투를 멈추며, 같은 항목 재선택은 플레이어 회복·크리프 재생성으로 두 공격을 다시 시험하게 한다. 기존 실제 AI 경로와 시험 종료 시 원정·인벤토리 복원을 유지한다.

In the existing F2 Creep melee entry, back away with `S` as each bite and two-punch attack finishes. Watch the feet and torso as pursuit resumes. Let the attack finish when inspecting this transition, since a just guard interrupts it. F2 pauses combat; reselecting heals and respawns for another cycle. The production AI path and restoration of the original expedition/inventory on exit remain.

**자동 검사 7종 통과:** `creep_locomotion_transition`, `creep_crawl`, `creep_enemy`, `creep_motion_reel`, `creep_ragdoll`, `creep_execution`, `test_room_session`. 실제 물기·양손 연타 끝 자세의 연결, 원본 걷기 자세로의 수렴, 정지/이동에 따른 보행 진행과 피격·처형·래그돌의 자세 제어를 확인했다. 최초 실행의 5종 통과와 수정 후 2종 재검사 통과를 합한 서로 다른 검사 7종이다.

초기 검사 실패 2건은 검사 기준을 바로잡은 뒤 재실행했다. 전환 검사는 스켈레톤 로컬값 대신 가져오기 스케일 약 0.3513을 반영한 실제 월드 미터로 측정하며 **16cm 한도는 그대로** 유지했다. 최종 두 공격의 관절 프레임 이동 최대값은 약 **10.67cm**다. 포복 처형 검사는 기존 기준본에서도 같은 실패를 재현했으며, 결정타 전 0.7초 자세와 1.02초 깊은 찌르기 반응을 비교하던 것을 실제 접촉 시점 자세 기준으로 고쳤다. 게임의 처형 동작은 바꾸지 않았다.

**실제 GPU 렌더·영상 검증 완료.** 같은 카메라에서 수정 전후 각각240프레임을 촬영했고 물기·연타→추격 전환 화면을 직접 확인했다. 오른발의 전환 순간 이동량은 약85cm에서3mm로 줄었으며 타격 횟수·추격 시작 시점은 동일하다. [8초 영상·전후 비교·검증 기록](../artifacts/validation/creep_transition_20260919/README.md).

**Seven distinct automated suites passed:** `creep_locomotion_transition`, `creep_crawl`, `creep_enemy`, `creep_motion_reel`, `creep_ragdoll`, `creep_execution` and `test_room_session`. Coverage includes actual bite/punch ending-pose continuity, convergence to source walking, stopped/moving gait progression and hit/execution/ragdoll pose ownership. This combines five passes from the initial run with two passing reruns after correcting their checks.

Two initial failures were addressed in the tests. Transition distances now use world metres with the imported approximately 0.3513 rig scale instead of skeleton-local units, retaining the **same 16cm limit**; the maximum final joint step across both attacks is approximately **10.67cm**. The crawl execution failure was reproduced on the unchanged baseline: it compared a 0.7s pre-contact pose against the 1.02s deep-stab recoil. The check now uses the actual contact pose, without changing gameplay execution motion.

**Actual GPU-render/video validation is complete.** Both versions were recorded for 240 frames with the same camera, and bite/punch-to-chase frames were inspected. Right-foot displacement at the transition fell from about 85cm to 3mm, with unchanged contact counts and chase timing. See the linked eight-second videos, comparison and validation record.

## 검증 절차와 상태 / Validation procedure and status

프로젝트 루트에서 관련 자동 검사를 실행합니다. / Run the relevant automated checks from the repository root:

```sh
GODOT_TEST_TIMEOUT_SECONDS=600 ./godot-game/tests/run_headless_tests.sh \
  creep_enemy cave_dungeon test_room
```

`creep_enemy`는 설치되어 있으면 실제 스킨·재질·클립·뼈 움직임, 타격 시점·가드·피해, 사망 보상·재시험·원정 복원을 검사합니다. 미설치이면 모델 관련 검사를 **SKIPPED**로 명시하고 기존 검지기 대체·설치 안내·초기화·상태 복원을 검사합니다. 미설치 검사의 통과는 크리프 외형이나 애니메이션 검증을 뜻하지 않습니다.

With the asset installed, `creep_enemy` checks geometry, materials, clips, bone movement, contacts, combat, rewards, repeated trials, and session restoration. Without it, asset checks are explicitly **SKIPPED**, while fallback and session behavior are checked. A missing-asset pass does not validate Creep visuals or animation.

자동 검사를 마친 뒤 [숨김 렌더링 규칙](../tests/EMBEDDED_RENDERING.md)에 따라 실제 GPU 촬영을 실행합니다. 매번 새로운 출력 이름을 지정합니다. / After automated checks, follow the hidden-rendering rules and use a new output name for each GPU capture:

```sh
CREEP_QA_ITERATION=review_01 GODOT_PREVIEW_TIMEOUT_SECONDS=360 \
  ./godot-game/tests/run_embedded_preview.sh creep_enemy_preview.gd
```

출력은 `godot-game/artifacts/visual_qa/creep/<이름>/`입니다. PNG를 직접 열어 몸체·방향·공격 접촉·사망 자세와 실제 폐광 배치를 검토해야 합니다. 2026-09-17 설치·미설치 자동 검사와 GPU 화면 10장 검토를 완료했습니다. [최초 실패·수정·통과 및 제한 사항](../artifacts/validation/creep_20260917/README.md)을 확인하세요.

Output is saved under `godot-game/artifacts/visual_qa/creep/<name>/`. Inspect the actual PNGs for shape, orientation, contacts, death pose, and mine placement. Installed and missing-asset checks and ten actual GPU renders were verified on 2026-09-17. The linked validation record retains the initial failure, correction, passing rerun and limitations.


[래그돌 적용 전 모션 기록 / Pre-ragdoll animation record](../artifacts/validation/creep_motion_reel_20260917/README.md): 22.53초, 30fps 실제 Godot 렌더. 걷기는 제자리로 표시한다. / Actual Godot rendering, with walking presented in place.


## 래그돌 사망 / Ragdoll death

2026-09-17 사용자 요청으로 사망은 짧은 피격 반응 뒤 물리로 전환한다. 원본 `death` 클립은 비교·제작용으로 보존한다. 손·발이 독립된 IK 루트이고 가져오기 스케일이 있으므로, 20개 실물 크기 물리체와 19개 제한 관절을 명시적으로 연결하고 원본 뼈대에 결과를 적용한다. 원본 메시·스킨은 바꾸지 않는다. 손가락·턱은 전환 순간 형태를 유지한다.

On request, death now hands off from a short hit reaction to physics. The source `death` clip is retained for reference. Twenty world-scale rigid bodies and nineteen limited joints explicitly connect the independent hand/foot IK roots and drive the untouched source skin. Fingers and jaw retain their handoff pose.

치명타 방향을 반영하며 월드와 충돌한다. 플레이어·살아 있는 적의 이동이나 무기 판정을 막지 않는 시체 전용 충돌층 32를 사용한다. 바닥·벽에 지지되고 움직임이 작아지면 물리를 고정한다. 처치 보상·적 수·귀환문은 사망 순간 한 번만 처리하며 시체 추가 타격으로 재발동하지 않는다. 사망 후 밀기·차기 기능은 이번 범위에 없다.

The impact direction influences collapse. Corpses collide with world geometry and other corpse bodies on physics layer 32, without blocking live actors or weapon queries. Once supported and quiet, the solved pose is frozen. Rewards/counts/extraction remain immediate and single-fire; corpse kicking is not included.

자동 검사: `./godot-game/tests/run_headless_tests.sh creep_ragdoll creep_ragdoll_trial creep_enemy creep_motion_reel test_room`
GPU 촬영: `CREEP_RAGDOLL_QA_ITERATION=<새 이름> GODOT_PREVIEW_TIMEOUT_SECONDS=600 ./godot-game/tests/run_embedded_preview.sh creep_ragdoll_preview.gd`

Automatic checks and GPU capture commands are above. F2 front/side/wall demonstrations are documented in TEST_ROOM.md.

[래그돌 실제 검증 영상·검사 결과 / Ragdoll video and verification](../artifacts/validation/creep_ragdoll_20260917/README.md).
