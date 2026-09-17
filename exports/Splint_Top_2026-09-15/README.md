# 가로 전완 · 상부 판자 부목

참고: https://youtu.be/KWOV8bPUCS8 (Far Cry 3 All Healing Animations). 여러 치료 중 몸 앞에 전완을 가로로 드는 구도를 왼팔에 적용했습니다. 사용자가 별도 시점을 지정하지 않아 가로 전완 구도로 해석했습니다.

팔을 가로로 유지하고 판자는 소매 윗면에 놓습니다. 9개 길이 방향 스킨 표면 표본으로 판자의 관통을 막고 접촉을 유지합니다. 붕대 상부 경로도 판자 바깥을 감싸도록 변경했습니다. 7.2초 사용·취소 규칙은 유지합니다.

검증: splint_motion, splint_test_room 통과. 접촉 오차 약 1mm, 손목 연결 간격 0. 235프레임 Vulkan/embedded 촬영 및 원정·커서·소스 보존. 전체 메시 면적의 충돌 검증은 아닙니다.

- splint_top.gif: 최종 동작
- contact_sheet.png: 단계별 실제 화면
- tests_final.log, test_room.log, capture_final.log, manifest.json: 검증 근거
