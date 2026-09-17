# 전완 근접 구도

전완을 몸 쪽으로 당기고 왼쪽 팔꿈치·위팔을 화면 밖에 배치했습니다. 카메라 확대 대신 실제 치료용 팔 위치를 변경합니다. 판자는 팔 위에 유지합니다.

검증: splint_motion 통과, 접촉 오차 약 1mm, 손목 간격 0. 실제 Vulkan/embedded 235프레임 촬영, 원정·커서·소스 보존 확인.

- splint_closeup_final.gif: 전체 동작
- contact_sheet_final.png: 주요 단계
- tests_final.log, capture_final.log, manifest_final.json: 검증 기록

오른팔은 바깥·아래 방향으로 경로를 바꿔 소매가 카메라를 관통하던 구간을 보정했습니다. 최종 캡처 close_forearm_02.
