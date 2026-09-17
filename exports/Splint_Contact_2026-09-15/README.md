# 나무 지지대 접촉 수정

붕대 여유 반경을 사용하던 지지대 위치를 실제 소매 삼각형의 스킨 변형으로 변경. 나무를 가져온 뒤 팔 아래 접촉점을 따라 고정합니다. 원본 에셋·기존 촬영 보존.

검증: splint_motion 통과. 고정 이후 감기·누르기 구간 양끝 윗면 접촉 오차 최대 약 1mm. 전체 면적의 충돌 검증은 아닙니다. Vulkan/embedded 235프레임 촬영, 소스·원정·커서 상태 보존.

- before_after.png: 2초 시점, 왼쪽 수정 전 / 오른쪽 수정 후.
- splint_contact.gif: 전체 동작.
- tests.log, capture.log, manifest.json: 검증 근거.
