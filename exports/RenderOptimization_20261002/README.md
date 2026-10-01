# GitHub 보존 상태 / GitHub publication status

로컬 최적화 커밋: `08a0d3ffb12c53fab5f6017462402c8d6418343c`. 전체 브랜치 푸시는 로컬 HTTPS Git 인증 부족으로 막혔습니다. 이 브랜치는 이번 작업의 27개 파일 패치와 검증 기록만 보존합니다. 기존 Unity 이전 소스가 필요하며 전체 소스 동기화나 독립 실행본이 아닙니다.

Local optimization commit: `08a0d3ffb12c53fab5f6017462402c8d6418343c`. Full-branch push is blocked by unavailable local HTTPS Git credentials. This branch preserves only the task patch for 27 files and its validation records. It requires the existing Unity migration sources; it is not full-source synchronization or a standalone build.

재적용 / Restore on the recorded baseline:

```sh
gzip -dc source.patch.gz > source.patch
git apply --check source.patch
git apply source.patch
```

`manifest.json`의 기준 커밋과 SHA-256을 확인합니다. / Check the baseline commit and SHA-256 hashes in `manifest.json`.

# Unity 빌드 최적화 / Unity build optimization — 2026-10-02

성능 모드에서도 많은 그리기 호출과 무거운 렌더링 준비·조명 처리가 남아 있었습니다. 최종 Mac 실행본에서 **GPU 시간 7.8%, 전체 프레임 시간 10.5%, 그리기 호출 기록 평균 31.8%**를 줄였습니다. 측정 구간은 여전히 약 79.6ms/프레임으로, **60FPS 또는 끊김 해결을 달성했다고 보고하지 않습니다**.

Performance mode still incurred many draw submissions and expensive rendering preparation and lighting. The final Mac player reduced **GPU time by 7.8%, wall frame time by 10.5%, and the draw-call recorder average by 31.8%**. The measured view still takes about 79.6ms per frame; **60FPS and elimination of frame drops are not established**.

## 반영한 변경 / Retained changes

- 은신처의 그림자를 만들지 않는 고정 돌 912개를 동일한 상태의 99개 메시 그룹으로 묶었습니다. 그림자를 만드는 110개 원본은 유지합니다. 원본 노드·충돌·재질·UV·법선 오프셋을 보존하고, 이동·활성화·재질·속성 변경을 감지하면 원본 렌더링으로 복귀합니다. / Combined 912 immutable, non-shadow-casting hideout stones into 99 compatible mesh groups. Retained 110 shadow-casting originals, source nodes, colliders, materials, UVs and normal offsets. Detected transform, activity, material or property changes restore original rendering.
- 알파 깊이 및 모션 기록 준비에 배열·재질 목록을 재사용하고, 같은 기록 단계에서 중복 재질 복사를 줄였습니다. 같은 프레임 안의 렌더러·재질 변경과 이전 프레임 모션 이력은 계속 반영합니다. / Reused alpha-depth and motion-history preparation storage and reduced repeated material copies within each recording pass. Live renderer/material changes and previous-frame motion remain effective.
- 성능 모드에서 은신처의 지정된 보조 점광원 17개 중 중요한 4개를 선택합니다. 거리·색·세기와 전환 안정성을 고려하며 주요 그림자 조명·휴대 횃불·마법·동적 조명은 이 예산의 대상이 아닙니다. / Performance mode selects four important lights from 17 designated hideout fill lights, considering energy, color, distance and stable transitions. Key shadow lights, carried torches, magic and dynamic lights are outside this budget.
- 월드와 장비 카메라를 반복해서 그린 뒤 횃불 그림자가 꺼진 상태로 남던 복원 순서 문제를 수정했습니다. 성능·화질 모드에서 실제 두 카메라의 반복 렌더링 후 조명 상태 복원을 검증했습니다. / Fixed restoration ordering that left carried-torch shadows disabled after repeated world/equipment camera rendering. Actual repeated camera rendering preserves light state in both modes.

## 동일 실행본 비교 / Same-player comparison

최종 build13의 실행 파일·게임 어셈블리 SHA-256이 일치하는 세 번의 **기존 경로 A1 → 최적화 B → 기존 경로 A2**를 비교했습니다. 위 세 가지 최적화만 함께 전환했습니다. 기존 10월 1일 컬링·그림자 명령 최적화는 모두 켜 두었고, 근거리 그림자 조명 제한은 3을 유지했습니다.

Compared **legacy A1 → optimized B → legacy A2** using the same final build13 executable and gameplay assembly hashes. Only the three retained optimization flags changed together. Existing October 1 culling/shadow-command optimizations remained enabled; the near-shadow light limit remained three.

| 측정 / Measurement | A1 | B | A2 | A1/A2 평균 대비 감소 / Reduction against A mean |
| --- | ---: | ---: | ---: | ---: |
| GPU ms | 90.849 | 83.311 | 89.948 | 7.8% |
| 전체 프레임 ms / Wall frame ms | 87.300 | 79.571 | 90.538 | 10.5% |
| 그리기 호출 기록 평균 / Draw-call recorder mean | 10,743.35 | 7,323.10 | 10,746.08 | 31.8% |

실제 Metal GPU, 1920×1080 월드·장비·UI 대상, 대상 MSAA 1, 은신처 화덕 고정 시점입니다. 각 실행에서 90프레임을 준비하고 60프레임을 측정했으며, 유효한 고유 GPU 표본은 58/58/60개였습니다. 측정 중 화면 읽기나 수동 카메라 렌더링을 하지 않았습니다. 숨겨진 백그라운드 실행이며 운영체제 입력·포커스·소리를 사용하지 않았습니다. 그리기 호출 기록에는 0 또는 중복 집계 프레임이 있어 평균을 보고합니다. 전체 게임 조작 중 FPS를 보장하는 측정은 아닙니다. GPU 약 83ms와 메인 스레드 약 65ms의 큰 비용이 남아 있습니다.

Measured actual Metal rendering at 1920×1080 world/equipment/UI targets, with target MSAA 1 and a fixed hideout hearth view. Each run warmed up for 90 frames and measured 60; valid unique GPU samples were 58/58/60. No readback or manual camera rendering occurred during timing. The hidden background player used no hardware input, focus changes or audio. Draw-call recorder samples can be zero or doubled, so averages are reported. This does not guarantee interactive whole-game FPS. Substantial costs remain: approximately 83ms GPU and 65ms main-thread time.

## 검증 / Validation

최종 실행본에서 다음 **3,697개 검사**가 모두 통과했습니다. 메시·변형·가시성·깊이·모션·상태 복원 및 실제 렌더링을 포함합니다. 정적 메시의 원본/결합 화면 8쌍을 확인했고, 보조 조명 제한에 따른 밝기 차이는 의도한 변경으로 분리했습니다. 준비 코드의 최적화 후보 색상 비교 54쌍과 깊이·모션 비교는 동일했습니다. 원본 반복 1사례에서는 색상 버퍼의 7바이트에 차이가 있었으며 허용 기준 안이었습니다. 모든 게임 화면의 픽셀 동일성을 뜻하지 않습니다.

All **3,697 checks** passed on the final player, covering geometry, mutation, visibility, depth, motion, restoration and actual rendering. Eight original/combined static-geometry image pairs were reviewed. Fill-light brightness changes are intentional. Preparation candidate color comparisons were exact across 54 pairs, as were depth/motion comparisons. One original-repeat control had seven differing color-buffer bytes within the acceptance bounds. This does not establish pixel identity for every game view.

| 검증 / Suite | 검사 / Checks | 사례 / Cases |
| --- | ---: | ---: |
| 정적 돌 결합 / Static batching | 2,642 | 804 |
| 컬링·렌더 준비 / Culling and preparation | 766 | 170 |
| 화질 설정·횃불 복원 / Quality and torch restoration | 75 | 11 |
| 보조 조명 예산 / Fill-light budget | 32 | 9 |
| 실제 플레이어 팔 / Player arms | 182 | 24 |

Unity 6000.3.25f1 Mac Development Mono 빌드 성공: 오류 0, 기존 경고 175, 산출물 3,272,244,452바이트. 로컬 앱 서명을 검증했습니다. 실행 위치는 `unity-game/Builds/MusimusihanRPG.app`이며 새 앱을 자동으로 전면 실행하거나 Dock 설정을 변경하지 않았습니다. 앞선 build4의 225단계 게임 스모크도 통과했지만, 렌더링 검사나 스모크는 Godot 전체 이전 완료를 뜻하지 않습니다.

Unity 6000.3.25f1 Mac Development Mono build succeeded: zero errors, 175 existing warnings, 3,272,244,452 output bytes. Local app signing was verified. The runnable app is `unity-game/Builds/MusimusihanRPG.app`; it was not brought to the foreground and Dock preferences were not changed. The earlier build4 passed its 225-stage gameplay smoke check; rendering acceptance and smoke tests do not establish complete Godot migration.

정적 결합은 제작된 고정 돌을 대상으로 합니다. 같은 메시 객체의 정점·법선·UV를 직접 바꾸거나 구성원 배열을 제자리 수정하는 작업은 자동 복귀 계약 밖입니다. 현재 게임에 그런 호출은 없습니다. 결합 메시의 넓어진 경계 때문에 모든 시점에서 호출 수가 감소하는 것은 아닙니다.

Static batching targets authored immutable stones. In-place edits of mesh vertices/normals/UVs or membership arrays are outside its fallback contract; current gameplay has no such callers. Wider combined bounds can increase submissions in an individual view.

## 제외한 후보 / Rejected candidates

근거리 그림자 조명 제한 3→1은 같은 실행본에서 GPU 시간이 약 86.6→160.7ms로 악화되어 되돌렸습니다. 원인은 확정하지 않았습니다. 보조 날씨 법선 단순화도 기본 비교의 작은 픽셀 변화가 일관되지 않아 최종 구성에서 제거했습니다. **성능·화질 모드 모두 원본 날씨 디테일을 유지합니다.** 앞서 후보를 포함해 측정한 15~20% 개선 수치는 최종 실행본의 수치가 아닙니다.

Reducing the near-shadow light limit from three to one regressed GPU time from approximately 86.6 to 160.7ms in its same-player comparison, so it was reverted; the cause is unconfirmed. Secondary weather-normal simplification was also removed because small primary-buffer variations were inconsistent, including controls. **Both modes retain the original weather detail.** Earlier 15–20% candidate gains do not describe the final player.

## 근거·재현·공유 / Evidence, reproduction and sharing

공유용 수치·SHA-256·검사 요약은 [receipt.json](receipt.json)에 있습니다. 절대 로컬 경로·환경·프로세스 정보·원시 예외는 제외했습니다. 세부 실행 영수증·이미지·로그는 Git 제외인 `unity-game/Artifacts/optimization-20261002/`에 보존합니다. 빌드·캐시·유료 원본 자료는 업로드하지 않습니다.

The [public receipt](receipt.json) records metrics, SHA-256 hashes and test summaries, omitting absolute local paths, environments, process information and raw exceptions. Detailed receipts, images and logs remain in the ignored artifact directory. Builds, caches and licensed originals are excluded from publication.

```sh
python3 tools/unity_migration/run_render_optimization_qa.py \
  --output-dir unity-game/Artifacts/render-qa-new \
  --acceptance static-batch draw-culling quality fill-budget player-arm
python3 tools/unity_migration/run_render_optimization_qa.py \
  --output-dir unity-game/Artifacts/render-benchmark-new \
  --benchmark-modes performance
```

기존 경로 비교에는 `--static-batching legacy --preparation legacy --light-budget legacy`를 함께 지정합니다. 실행기는 기존 출력 폴더를 덮어쓰지 않으며, 자신이 만든 검증 프로세스만 정리합니다. 로컬 Git·LFS 인증과 GitHub 플러그인 연결은 별개입니다. 전체 브랜치 푸시가 막힐 경우 작업 커밋과 작업 한정 소스 패치·이 기록·영수증의 별도 GitHub 보존을 구분해 보고합니다. 패치는 기존 Unity 이전 소스가 필요하며 독립 실행본이나 전체 브랜치 동기화가 아닙니다.

For the legacy comparison, add `--static-batching legacy --preparation legacy --light-budget legacy` together. The runner refuses to overwrite an output directory and cleans up only its own QA processes. Local Git/LFS authentication is separate from the GitHub plugin connection. If full-branch push is blocked, report the local commit separately from publication of its task-only source patch, report and receipt. The patch requires the existing Unity migration sources; it is not a standalone build or full-branch synchronization.
