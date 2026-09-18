# 포복 크리프 처형 검수 / Crawling Creep execution validation

2026-09-18 — 다리를 잃고 착지·회복을 마친 크리프를 검으로 찌르는 첫 처형 동작입니다. 가까운 몸통을 조준하고 LMB를 0.4초 이상 누른 뒤 놓습니다. F2 기본 메뉴의 `크리프 처형 · 포복 찌르기` 또는 `크리프 처형 · 양다리 포복`에서 반복할 수 있습니다.

The first execution stabs a living leg-severed Creep after physical landing and prone recovery. Aim at its nearby torso, hold LMB for at least 0.4 seconds, then release. Both crawling-execution entries in the F2 basic menu provide repeatable fixtures.

## 실제 실행 영상 / Actual runtime video

[18초 영상 / 18-second video](creep_execution.mp4)

| 시간 / Time | 사례 / Case |
| --- | --- |
| 0–6초 / seconds | 왼다리 절단 · 1인칭 / Left-leg loss, first person |
| 6–12초 / seconds | 같은 기능을 측면에서 별도 재실행 / Separate side-view repeat of the same feature |
| 12–18초 / seconds | 양다리 절단 · 1인칭 / Both-leg loss, first person |

수정한 프로젝트의 실제 플레이어·크리프 코드와 GPU 렌더링을 사용했습니다. 입력은 생산 코드의 차지·놓기 함수를 60Hz로 호출합니다. 실제 부위 타격과 물리 낙하·회복으로 대상을 준비한 뒤 촬영하며, 촬영 중 적의 이동 AI만 정지시켜 접촉을 관찰합니다. 별도 시험 바닥에서 촬영한 영상이며 던전에서 사용자가 직접 조작한 녹화는 아닙니다. 측면은 1인칭 팔 장비와 적의 접촉을 확인하는 별도 실행으로, 완전한 3인칭 캐릭터 애니메이션을 뜻하지 않습니다.

This is actual GPU rendering of the modified project's player and Creep code, driven through production charge/release APIs at 60Hz. Setup uses real localized hits, physical landing and recovery; enemy travel AI is paused during capture to inspect contact. The video uses an isolated inspection floor, not manual dungeon play. The side view is a separate run inspecting the first-person equipment rig against the enemy, not a complete third-person player animation.

- 960×540, 30fps, 540프레임, 18.00초, 무음. MP4 전체 디코딩 540프레임 통과.
- 최종 반복 `final_04`: 실패 목록 없음. PNG 39장은 [stills](stills/)에 보존했습니다.
- 세 사례 모두 실제 몸통 피부 삼각형 접촉, 한 번의 처치·보상, 사망 랙돌을 확인했습니다.
- 1.50m에서 약 0.35m 실제 접근 후 찌릅니다. 접촉 자세에서 오른쪽 어깨 이동 보정은 모두 0m이고 기존 상완 0.34m·전완 0.26m 길이를 유지합니다.
- 칼끝은 0.82초에 몸통 안으로 약 10cm 들어가며, 몸통과 같은 깊이 처리를 사용합니다. 전체 동작은 1.55초입니다.

The silent 960×540 H.264 video contains 540 frames at 30fps; full decoding passed. Final iteration `final_04` has no failures, and all 39 PNG stills are retained. All three cases confirm actual posed-skin contact, one defeat/reward and death ragdoll. A physical approach of approximately 0.35m from 1.50m preserves the 0.34m/0.26m arm lengths with zero right-shoulder correction at contact. Impact occurs at 0.82 seconds, penetrating approximately 10cm through shared world depth, within a 1.55-second action.

## 자동 검사 / Automated checks

서로 다른 관련 검사 7종이 통과했습니다. [logs](logs/)에는 개선 과정의 초기 실패와 최종 통과를 함께 보존합니다. 모든 로그가 처음부터 통과한 것은 아닙니다.

Seven distinct relevant suites passed. Logs retain early failures as well as subsequent passes; not every intermediate run passed.

| 검사 / Suite | 통과 근거 / Passing evidence |
| --- | --- |
| `creep_execution` | `creep-execution-final07.log` |
| `creep_execution_trial` | `creep-execution-reach06.log` |
| `creep_dismemberment_trial` | `creep-execution-related04.log` |
| `enemy_execution` | 해당 검사 통과: `creep-execution-core02.log` / Individual suite passed in this mixed-result run |
| `sword_shield_execution` | 해당 검사 통과: `creep-execution-first-test.log` / Individual suite passed in this mixed-result run |
| `first_person_renderer` | `creep-execution-reach06.log` |
| `test_room` | `creep-execution-final-headless05.log` |

검사 범위: 한쪽·양쪽 다리의 실제 절단과 착지·회복, 높은 체력의 포복 대상, 검·방패 및 방패 수납, 실제 피부 접촉, 접촉 전 생존, 단일 처치·보상, 취소·대상 소멸·장애물·거리, F2 정지·재개·초기화, 복제 조명과 장비 깊이 복원, 기존 원정·가방 보존. 초기 프레임 경계 종료, 제거된 대상 접근, 새 메뉴 등록 검사 실패는 수정 후 관련 검사에서 통과했습니다.

Checks cover real single/both-leg severing and recovery, high-health crawlers, carried/stowed shields, actual skin contact, no premature damage, one defeat/reward, cancellation/removed targets/walls/range, F2 pause/replay/reset, mirrored-light and depth restoration, and original session/inventory preservation. Early duration-boundary, detached-target and menu-registration failures were fixed and their relevant checks passed afterward.

## 범위와 자료 / Scope and records

경사·계단·크기가 다른 적의 접근과 접촉, OS 입력을 이용한 수동 던전 플레이는 미확인입니다. 일반 테스트룸의 기존 ObjectDB 2개 종료 경고는 남아 있습니다. 영상에 보이는 기존 모델·상처와 하체 포복 기능은 보존했으며 이번에 새로 제작한 에셋으로 주장하지 않습니다. 원본 모델과 라이선스 에셋은 기존 위치에 남겨 두었습니다.

Slopes, stairs, differently sized enemies and manual OS-input dungeon play are unverified. The general test-room suite retains its existing two-ObjectDB exit warning. Existing models, wounds and lower-body crawling are preserved; this task does not claim to have authored them. Source and licensed assets remain in their original locations.

- [동작·조작 안내 / Feature guide](../../../docs/CREEP_EXECUTION.md)
- [GPU 기록 / GPU manifest](render_manifest.json)
- [집중 물리 검사 / Focused physics report](physics_report.json)
- [영상 해시와 검증 요약 / Video hash and validation summary](validation_summary.json)

영상과 코드는 해당 작업의 GitHub 브랜치에 함께 게시하며, 최종 원격 커밋 및 LFS 영상 해시 확인은 게시 작업에서 별도로 기록합니다.

The video and code are published together on the task's GitHub branch. Remote commit and LFS video-hash verification are recorded separately during publication.
