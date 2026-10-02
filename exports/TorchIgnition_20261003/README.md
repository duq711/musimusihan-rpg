# Unity 횃불 3초 점화 자료 / Three-second torch ignition archive

이번 작업의 코드·UI·오디오 연결·검증·문서 변경 24개를 `source.patch.gz`에 저장했습니다. 적용 기준은 로컬 Unity 이전 커밋 `fa459ca728cbba23ca80c3cca7b28dcb3538949f`이고 작업 커밋은 `792c358a560150ba89a290db55f0a1d409e97cc9`입니다. 패치를 기준 파일에 적용한 뒤 모든 결과의 SHA-256 일치를 확인했습니다. `manifest.json`은 파일 해시, `receipt.json`은 비식별 측정 근거입니다.

This archive stores all 24 task files as a compressed patch, based on local Unity migration commit `fa459ca728cbba23ca80c3cca7b28dcb3538949f` and task commit `792c358a560150ba89a290db55f0a1d409e97cc9`. Applying the patch to the baseline files reproduced every recorded SHA-256. The manifest records hashes; the receipt records sanitized measurements.

로컬 Git 인증 문제로 전체 Unity 이전 브랜치의 push는 완료하지 못했습니다. 이 자료는 기존 Unity 이전 파일·에셋이 필요한 작업 차이이며, 독립 실행 가능한 전체 프로젝트 또는 전체 브랜치 동기화를 뜻하지 않습니다. 설치된 Mac 실행본과 원본 에셋은 로컬에 보존합니다.

Local Git authentication blocked pushing the full migration branch. This task delta requires the existing migration files/assets and is not a standalone project or confirmation of full-branch synchronization. The installed Mac app and source assets remain preserved locally.

복원 / Restore: `gzip -dc source.patch.gz | git apply --check -`, then apply without `--check` from the required baseline checkout. Verify results against `manifest.json`.

---

# 횃불 3초 점화 / Three-second torch ignition — 2026-10-03

**빌드 24를 기존 Dock 실행 위치에 설치했습니다.** 게임을 다시 실행하면 F/L → 중앙 원형 진행 표시와 남은 숫자 → 3초 뒤 켜진 횃불·왼손이 즉시 휴대 자세로 나타나는 흐름을 사용합니다. 손으로 꺼내는 동작은 생략합니다. 원은 위에서 시계 방향으로 한 바퀴 채워지고 숫자는 소수 첫째 자리까지 표시합니다.

준비 중 0 / 0.85 / 1.70 / 2.55초에 부싯돌 타격음을 재생합니다. 기존 금속 충돌 클립을 2D 음원·pitch 1.4·volume 0.18로 재사용하며 새 에셋이나 공유 음량 변경은 없습니다. 실제 클립의 비어 있지 않은 PCM·연결·타격 횟수를 검증했고 사용자 작업을 방해하지 않도록 자동 시험에서는 소리를 끕니다. 스피커 청취를 인증하지는 않습니다.

F/L 재입력은 준비를 취소하고 켜진 횃불은 끕니다. 장비 해제·손 장비 교체·가방·상자·치료·야영·검토·사망은 완료 예약을 취소합니다. Esc/F2 일시정지는 남은 시간을 보존합니다. `motion_torch` 재시험은 새 3초를 시작하고, 시험 종료는 원래 플레이어·가방·남은 시간·타격 횟수를 복원합니다. 거절된 점화는 성공이나 껐다는 안내를 하지 않습니다. 시간은 실제 플레이어 진행에서만 소비하며 렌더링/자세/HUD 갱신은 중복 진행하지 않습니다.

최종 빌드에서 **새 검사 3,488개 통과**: F/L 실경로, 2.999초/3초 경계, 원의 각도와 숫자 위치, 숨겨진 준비 모델/조명, 즉시 완전 휴대 자세, 4회 타격·PCM, 30/60/120Hz 분할, 취소·재시작·장비·상태 중단, pause/F2 재개·재시험·초기화 및 원래 점화 복원입니다. 휴대 검사는 역사 입력 413개를 유지하고 완전 휴대 249개 표본의 자세·손/불꽃을 비교합니다. 사용자 새 규칙은 Godot의 이전 즉시 점화·꺼내기 동작을 대체하며 원본·역사 JSON은 변경하지 않았습니다. 다른 렌더 시험의 명시적 켜짐 프리셋은 사용자 점화와 구분합니다.

그래픽 개선 빌드 19의 **720p 월드·장비 / 1080p UI·문자, 스캔 밉맵·공간 AA·반사광 보정**을 유지했습니다. 같은 최종 24 실행본에서 세 경로 3,600구간씩 다음 기준을 통과했습니다: uncapped wall/GPU p99 ≤16.667ms, wall 최대 ≤33.333ms. 각 측정 창에서 월드·장비 타깃 재할당은 0입니다.

| 경로 / Route | 평균 FPS / Mean | wall p99 ms | GPU p99 ms | wall max ms |
|---|---:|---:|---:|---:|
| hideout | 105.3 | 13.686 | 9.909 | 16.901 |
| dungeon | 172.0 | 9.407 | 16.281 | 18.357 |
| cave | 148.5 | 10.199 | 6.469 | 13.642 |

이는 횃불이 켜지고 카운트다운은 숨겨진 상태의 RPG 단독 실행·백그라운드 생산 프레임 카메라 경로입니다. 모든 프레임 고정 60FPS, 전경 전체 플레이·물리 이동/전투·점화 중 HUD의 프레임 시간은 인증하지 않습니다. 화면 읽기는 측정 창 이후에만 수행했습니다.

Universal Release Mono Mac 빌드 오류 0 / 경고 176, 엄격한 로컬 서명·설치 DLL SHA 확인을 통과했습니다. DLL SHA-256 `adf9f332e90c8d739101679a36ac1bbec8ec8ee2f8fbedea0331f68698dc76cd`. 기존 앱 루트·Dock·Applications 연결을 보존했고 사용자 앱을 종료하지 않았습니다. 이전 빌드는 ignored `Artifacts/performance60-20261002/PreviousInstalledBuild-before-24.app`에 있습니다. 새 검사·사진·소스 동결 및 반복 빌드 자료는 ignored `Artifacts/torch-ignition-20261003/`, 격리 빌드 도구는 `Artifacts/performance60-20261002/`에 있습니다. [비식별 근거](torch-ignition-20261003.json)에 90개 소스 해시와 새 최종 검증을 기록했습니다.

---

**Build 24 is installed at the existing Dock target.** Relaunch the game: F/L starts a clockwise three-second circular countdown with remaining seconds inside. The torch, light and fitted left hand appear immediately in the carry pose at completion; the reaching animation is skipped.

Four flint impacts use the existing packaged metallic transient at 0 / .85 / 1.70 / 2.55 seconds, through an owned 2D source at pitch 1.4 and volume .18. Actual non-silent PCM, clip routing and event crossings were verified while automated speaker output stayed muted. No hardware audition is certified.

F/L cancels preparation or extinguishes a lit torch. Inventory/hand equipment changes, chest interaction, treatment, camp, review and death cancel pending completion. Pause/F2 preserves time; retry prepares a fresh three seconds. Exiting F2 restores the same original player, bag, timer and strike count. Rejected ignition returns failure without a misleading extinguish notice. Only player advancement consumes time; pose/HUD/render refreshes do not.

The final build passed **3,488 fresh checks**, including actual shortcuts, exact deadline boundaries, circular geometry/centered digits, hidden pending torch/light, immediate carry, audio routing, 30/60/120Hz timing partitions, cancellation and F2 restoration. The carry fixture retains 413 historical inputs and checks 249 fully carried source poses. This user override supersedes immediate Godot ignition/draw behavior; original sources and historical JSON remain preserved.

Build 19's 720p world/equipment, 1080p UI/text and clarity improvements remain. All three fresh 3,600-interval routes on this exact final build passed the unchanged strict 60FPS capacity criterion in the table. Target reallocations were zero. These are quiet, hidden production-frame camera sweeps with a lit torch and inactive countdown; they do not certify constant 60 on every frame, full foreground play, physical movement/combat, pending-HUD timing or other hardware. Readback occurs after timing.

The universal Release Mono Mac build passed compilation (0 errors / 176 warnings), strict signing and installed assembly verification. The existing app root and Dock/Applications links remain; no user process was terminated. The linked sanitized receipt records 90 frozen source hashes and fresh final-build evidence. Raw artifacts and previous build are preserved in the ignored locations above.
