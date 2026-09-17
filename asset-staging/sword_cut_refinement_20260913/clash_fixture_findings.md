# 기본 베기와 실제 검격 접촉 조사

2026-09-13. 변경 범위는 `godot-game/tests/sword_clash_test.gd`의 자연 교전 fixture이며 게임 코드·모델·모션 JSON은 수정하지 않았다.

## 기존 fixture의 실패

플레이어와 적을 `(0, 바닥, 0)`, `(0.1, 바닥, -1.7)`에 두고 두 ACTIVE를 동시에 시작한 시험은 보존한 기준 모션과 V3에서 모두 검격이 발생하지 않았다. 두 경우 모두 플레이어 체력은 100→79, 적은 82를 유지했다. 따라서 기존 자연 검격의 3개 실패는 이번 기본 베기 변경으로 생긴 회귀가 아니다. 기준 모션은 파일을 덮어쓰지 않고 해당 진단 프로세스의 `ReferenceSwordMotion._clips` 캐시만 교체했다.

- 실제 추적: `clash_diagnostic_v3.json`, `clash_diagnostic_v3.log`
- 보존한 진단 코드: `sword_cut_clash_diagnostic_original.gd`
- SAT 프록시 분석: `analyze_clash_proxies.py`, `clash_proxy_analysis_v3.json`

V3의 동시 ACTIVE 0.0833초 표본은 검날 겹침을 만들려면 플레이어 검 프록시를 최소 약 1.22m 옮겨야 했다. 앞뒤 깊이만 바꿔서는 겹치지 않는다. 0.1333초에는 깊이 약 0.326m 이동으로 접촉할 수 있지만 적의 0.09초 피해 시각 이후다. 이 fixture에 맞춰 자연 베기를 왜곡하는 것은 적절하지 않다. 수치는 각 표본의 실제 OBB와 현재 0.02m 접촉 여유를 이용한 기하 계산이며 제작 제안 값이 아니다.

README의 계약은 ‘동시에 휘두른 실제 검날 모델이 겹치면’ 상쇄한다는 것이다. 동일한 ACTIVE 시작 시각, 고정 거리 1.7m, 접촉 없는 자동 상쇄는 문서화되어 있지 않다.

## 교체한 자연 교전 fixture

적을 `(0.25, 바닥, -1.1)`에 놓고 플레이어를 정확히 바라보게 한다. 적의 실제 WINDUP을 0.4초 진행한 뒤 플레이어가 `begin_sword_attack("right_diagonal")`과 실제 release 요청 경로를 사용한다. 이후 양쪽의 상태·자세·피해 해결을 정상 순서대로 진행한다. 적도 실제 0.7초 WINDUP으로 ACTIVE에 진입한다. 어느 쪽도 상태 시각·피해 마감·검날 변환을 강제로 바꾸지 않는다.

진단에서 플레이어 ACTIVE 0.1333초 / 적 ACTIVE 0.0667초에 두 실제 검날 OBB가 겹쳤다. 플레이어는 RECOVERY, 적은 STAGGER로 바뀌었고 체력은 각각 100 / 82였다. 이는 플레이어 0.145초 / 적 0.09초의 피해 마감보다 앞선다. 시험은 실제 모델 겹침, 양쪽 마감 이전 접촉, 회복·경직, 양쪽 피해 취소를 확인한다. 기존 기하/SAT·겹치지 않음·비활성·맨손 제외 검사도 그대로 유지한다.

- 실제 추적: `clash_diagnostic_fixture_v3.json`, `clash_diagnostic_fixture_v3.log`
- 보존한 진단 코드: `sword_cut_clash_diagnostic_fixture.gd`
- 조사 당시 현재 모션 파일 SHA256: `0a53c2a91abdc322997777998c0bd62b6754486392ab2c7f0b5ce726da9f5795`

진단 wrapper는 손 통합 중 `sword_long_grip_visual.gd:295`의 static thumb vertex assertion을 감지하여 exit 1이었다. 위 접촉 결과는 실제 실행 추적이며 전체 테스트 PASS라는 뜻은 아니다. 손 통합 완료 후 정규 `sword_clash` wrapper 검증을 수행해야 한다. 진단 스크립트는 모두 staging으로 옮겨 `tests/*_test.gd` 자동 발견에서 제외했다. fixture 변경의 `git diff --check`는 통과했다.
