# 오크 적 통합 검증 / Orc enemy validation — 2026-09-17

> **사용자 요청으로 적용 취소됨 (2026-09-17).** 게임과 테스트룸에서 제거한 에셋의 제작/과거 검증 기록이다. 현재 게임의 적용 상태가 아니며 재적용하지 않는다. 원본과 기록만 보존한다.
> **Withdrawn at the user’s request (2026-09-17).** This is a preserved source/historical validation record, not the current game state. Do not reapply the removed asset.

## 결과 / Result

제공된 리깅 오크·양손 도끼·텍스처·12개 애니메이션을 추가했다. 테스트룸 `F2 → 기본 → 오크 · 도끼 근접 전투`, 실제 폐광의 동쪽 창고 적에 연결했다. 기존 던전 적 수 6명, 원래 창고 적의 수치, 방패 방어·저스트 가드·처치 보상·귀환문 조건을 유지했다.

Added the supplied rigged orc, two axes, textures and 12 animations. Connected a real test-room duel and the eastern mine store encounter while retaining enemy counts, existing stats, blocking, parry, rewards and extraction rules.

## 검사 / Checks

- `orc_enemy`: PASS. 실제 스킨·뼈·원본 클립 변형, 3종 공격의 준비/활성/복귀 연속 표본, 실제 타격 프레임, 방패 완전 방어·저스트 가드 경직·무방비 피격, 오크 피격·사망·1회 보상·마지막 자세 유지, 테스트룸 재선택·회복·초기화·원정과 커서 복원.
- `shield_guard`: PASS. 기존 방패 규칙 회귀. 기존 종료 시 ObjectDB 2개 누수 경고가 있으나 검사 오류는 없었다.
- `cave_dungeon`: PASS. 실제 오크 1명 포함 6명, 지형 충돌/배치, 기존 함정·상자·원정 탈출과 재시작.

All three suites passed. The orc suite exercises real production combat and lifecycle behavior; the cave suite confirms the new archetype in the original encounter. The shield suite reports two ObjectDB instances at shutdown as a warning, without test failure.

## 실제 화면 / Actual rendering

Mac Apple M4 / Godot 4.7 / Vulkan Forward+ / embedded 숨김 렌더. 원본 공격 3개와 피격 클립을 10구간씩 촬영해 타격 시점을 선택했다. 최종 정면·측면·후면·달리기·세 공격·피격·사망 9장과 실제 폐광 1인칭 화면을 촬영했다. 첨부는 그중 정면·타격·폐광 원본 PNG다. `manifest.json`은 실제 모델 해시와 상태 표본을 기록한다. 생성 이미지가 아니다.

Actual hidden GPU renders were inspected: front/side/back, running, three strikes, hit and death, plus the real mine scene. Source-clip timing was inspected separately in 40 rendered samples. Attached PNGs come from the game renderer; they are not generated concept art. The mine screenshot uses the original scene, spawn and lighting; HUD location text remains the initially loaded entry label because gameplay polling is disabled during capture.

## 범위 / Scope

- 기본 AI에는 대기·걷기/달리기·3종 공격·첫 피격 반응·사망을 연결했다. idle2/roar/jump/wound는 가져오고 보존했지만 새 AI 행동으로 추가하지 않았다.
- 기존 근접 판정은 거리·정면·시야 검사다. 도끼 메시가 피부에 닿는 정밀 판정으로 바뀐 것은 아니다. 도끼에는 검 전용 검날 충돌 프록시가 없고 실제 방패 방어를 사용한다.
- 테스트용 상태 입력·숨김 렌더를 사용했다. OS 키보드/마우스의 실시간 수동 플레이는 미확인이다. 사용자 창·커서·실행 중인 게임은 조작하지 않았다.
- 원본 Downloads 파일은 그대로 보존한다. 게임용 SCN 106MiB, 사용 원본 ZIP 약 147MiB와 텍스처는 Git LFS로 관리한다.

Only the listed AI actions are wired; remaining clips are preserved. Combat keeps its existing range/facing/line-of-sight model, not mesh-level axe contact. Validation used scripted local state inputs and hidden rendering, not manual OS input. User windows and the running game were not controlled. Large runtime/source binaries use Git LFS.
