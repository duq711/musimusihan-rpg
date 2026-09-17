# 검격 충돌 fixture 독립 진단 · 2026-09-13

기존 `sword_clash_test.gd`의 자연 충돌 조건 `(x=0.25, z=-1.1, enemy lead=24/60초)`은 이번 direct entry를 꺼서 기존 준비 동작으로 실행해도 실패합니다. 진단 복사본에서 `begin_sword_attack()` 직후 해당 프로세스의 player 인스턴스에 `_sword_direct_entry=false`만 적용했습니다. 원래 게임 소스·시험 파일·검 변환·충돌 마진은 수정하지 않았습니다.

- `baseline_same_fixture.log`: 기존 준비 동작에서도 overlap=false, 두 clash 시간 INF. 플레이어 체력 79, 적 체력 82. 자연 충돌 관련 5개 기대값 실패.
- `twelve_ready_placements.log`: 발검 완료 및 같은 READY/모션시계/카메라/팔 상태를 복구한 현재 동작에서 가까운 12개 위치·타이밍 검사. 성공 조건 없음.
- `right_075_ready_placement.log`: 부모 요청의 추가 `(x=0.75,z=-1.1,lead=24)` 검사. 성공 조건 없음. 실제 양쪽 검 중심과 전투 시계를 프레임별 기록.

13개 위치·타이밍은 `summary.json`에 보존했습니다. 모두 일반 actor 위치와 실제 WINDUP→ACTIVE 갱신만 사용했습니다. 검 부품 이동이나 margin 확대는 하지 않았습니다. 마지막 조건의 player ACTIVE 0.1333초에서 검 중심은 `(0.6317,1.6923,-0.6589)`, enemy ACTIVE 0.0667초에서 검 중심은 `(-0.3769,1.7778,-1.5789)`로 서로 다른 궤적을 지나갑니다. 중심 간 거리만으로 충돌을 판정한 것은 아니며, 통과 조건은 계속 실제 원래 OBB overlap과 양쪽 무피해였습니다.

이 결과로 direct entry의 충돌 회귀라고 판정할 수 없습니다. 기존 fixture와 복원된 원본 공격 동작이 맞지 않는 실패로 남겼습니다. 좁은 탐색에서 검증된 대체 fixture를 찾지 못해 검색을 종료했습니다. 임시 `*_diagnostic_test.gd`는 정규 tests 폴더에서 이 폴더로 옮겼습니다. 모든 실행은 기존 낮은 우선순위 headless wrapper를 사용했습니다.
