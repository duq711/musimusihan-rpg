# 8~12초 참고 동작

참고 영상: https://youtu.be/KWOV8bPUCS8?t=8 — 브라우저에서 8~12초 구간을 프레임 단위로 관찰했습니다. 펼친 왼손을 내밀고 팔을 당겨 주먹을 쥔 뒤 반대 손으로 감아 누르는 흐름을 기존 7.2초 부목에 적용했습니다. 원본 영상의 4초 길이나 카메라 움직임을 그대로 복제한 것은 아닙니다.

- 팔 내밀기/당김과 손목 회전 추가
- 소지부터 검지까지 순차적으로 닫고 엄지가 뒤따르는 주먹
- 감는 동안 팔의 작은 반응, 오른손 재파지/윗면 누르기 유지
- 팔꿈치 화면 밖, 팔 위 판자, 밀착 붕대 유지

검증: splint_motion 통과, 실제 Vulkan/embedded 235프레임 및 상태·소스 보존 확인.

산출물: splint_reference_motion.gif, contact_sheet.png, manifest.json, tests.log, capture.log.
