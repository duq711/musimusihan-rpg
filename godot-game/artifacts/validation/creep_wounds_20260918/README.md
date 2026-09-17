# 절단면 검수 / Wound validation — 2026-09-18

평평한 분홍 단면을 목 보존·양면 안쪽 깊이·다양한 조직색·작은 뼈 중심·짧은 출혈·월드 접촉 혈흔으로 교체했습니다. 원본 GLB와 별도 진행 중인 처형·포복 조정 작업은 보존했습니다. 최종 공개 커밋은 원격 최신 절단·래그돌·포복 내역 위에 이번 단면 변경만 추가합니다.

Replaced the uniform pink cap with a retained neck, recessed tissue on both sides, varied tissue colors, a small bone core, a short burst and world-contact stains. Original assets and separate in-progress execution/crawl changes are preserved. The final publication commit preserves the latest remote severance/ragdoll/crawl history and adds only this wound update.

## 실행 결과 / Executed checks

- 형상: 10개 닫힌 단면, COLOR/UV/정규화 가중치, 피부 표면 보존, 원본 해시 보존. 17클립의 85자세에서 양쪽 경계 틈 0m. `build_report.json`, `geometry_report.json`.
- 실제 원본 작업트리: `creep_dismemberment`, `creep_dismemberment_trial`, `creep_knockdown`, `creep_crawl`, `creep_ragdoll`, `creep_hit_query`, `test_room_session` 통과.
- 무관한 처형 변경을 제외한 독립 게시 후보: `creep_wound`, `creep_hit_query`, `located_hit_path`, `creep_enemy`, `test_room` 통과. 최종 모델 재가져오기 후 `creep_wound` 재검사 통과. 고유 자동 검사 총 11개.
- 새 시험: 카탈로그 → 실제 타격 → 출혈·양면 단면 → F2 정지 → 재선택·초기화 → 원정/인벤토리 원래 참조 복원. 효과 수명·수량 제한·월드 접촉·부모 제거 시 정리도 통과.
- 창 없는 실제 embedded Vulkan GPU에서 1280×720 화면 12장 생성. 단면의 과도한 반사와 혈흔 뒷면 가림을 실제 화면에서 수정. 마지막 변경은 내부 명암과 촬영 각도만 보정했으며 GPU 재검수로 확인.

Geometry checks passed for ten closed caps and 85 animated poses with zero seam gap. Eleven distinct automated suites passed across the original worktree and an isolated publication candidate that excludes unrelated execution work. The final wound check covers imported geometry, both cut surfaces, emission/contact/pause/expiry/cleanup, F2 replay and expedition restoration. Twelve actual embedded Vulkan GPU stills were captured; the final shading/camera-only adjustments were checked by rerendering.

## 실패에서 수정한 내용 / Corrected failures

첫 wound 검사는 새 GLB를 Godot에 다시 가져오기 전의 옛 단면 캐시를 읽어 COLOR/깊이 검사에서 실패했습니다. 다시 가져온 뒤 통과했습니다. 독립 게시 후보의 첫 테스트룸 검사에서는 새 `creep_wound` action의 테스트 허용 목록이 빠져 실패했고, 항목 추가 후 해당 검사만 재실행해 통과했습니다. 첫 GPU 검수에서는 뒤집힌 평면 혈흔과 과도한 부채꼴 반사를 발견해 양면 렌더링·단면 삼각형 재분포·미세 요철·반사 강도를 보정했습니다.

The first wound run used stale imported geometry and failed its color/depth checks; reimport fixed it. The candidate's test-room allowlist omitted the new action; adding it and rerunning that suite passed. GPU review identified backface-hidden stains and fan-shaped highlights, corrected through two-sided stain rendering, redistributed cap vertices, finer relief and lower specular strength.

## 화면과 남은 범위 / Images and limits

`head_cut.png`, `right_arm_cut.png`, `left_leg_cut.png`은 실제 타격 후 0.4초입니다. `_part`는 본체 가림을 해제한 분리 부위 단독 검수(본체만 숨기고 실제 부위·물리·재질은 유지), `_settled`는 물리 접촉·혈흔, `_intact`는 절단 전입니다. 머리·다리 자세와 지면 방향에 따라 단면이 가려질 수 있으므로 여러 각도의 화면을 함께 봅니다. `manifest.json`에 실제 renderer·소스 해시·원정 복원 검증을 기록했습니다.

The cut images are 0.4 seconds after two actual hits. Part images hide only the occluding body for diagnostic inspection of the unchanged physical detached mesh; settled and intact images retain the full scene. Wounds can be occluded by pose or floor orientation; review multiple views. The manifest records the actual renderer, source hashes and restoration checks.

고정된 관절 부위 절단이며 임의의 공격 평면 절단·유체 시뮬레이션은 구현하지 않았습니다. 기존 일반 테스트룸의 ObjectDB 종료 경고 2개는 남아 있습니다. 캡처는 격리된 스튜디오 장면으로, 실제 사용자 하드웨어 입력·OS 포커스 시험은 아닙니다. 라이선스 원본과 파생 GLB는 로컬 전용입니다.

Cuts remain at fixed anatomical regions; arbitrary cutting planes and fluid simulation are outside this implementation. The general test-room suite retains two existing ObjectDB exit warnings. Captures use an isolated studio fixture, not hardware input or OS-focus validation. Licensed source and derived GLBs remain local.

원격 동시 작업 반영: 원격 `77ab009`의 기존 구현을 보존한 별도 후보에서 `creep_wound`, `test_room`, `test_room_session`을 다시 실행하여 3개 모두 통과했다. 최종 코드 해시는 `publication_code_hashes.json`, 실행 로그는 `remote_candidate_pass.log`에 기록한다. 이전 로그는 재현 이력이다. / The final candidate retains remote commit `77ab009` and passed all three focused suites for wounds, the test room and session restoration. Final hashes and the execution log are recorded separately; earlier logs preserve the iteration history.
