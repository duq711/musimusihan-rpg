# 굵은 팔 체형

전완 반경 1.45배, 위팔 반경 1.35배. 원본 모델은 보존하고 공통 supplied_fp_arm.gd에서 팔 길이와 손 기준점을 유지하는 반경 변형을 적용했습니다.

자동 검증: supplied_fp_arms, splint_motion 통과. 실제 Vulkan/embedded 235프레임 촬영 및 상태·원본 보존 확인.

- before_after.png: 왼쪽 변경 전, 오른쪽 변경 후, 동일 시점·카메라.
- splint_soldier_arms.gif: 변경 후 전체 부목 동작.
- manifest.json, tests.log, capture.log: 검증 근거.

기존 부목의 붕대가 소매 위에서 뜨는 표현은 이번 체형 변경과 별도의 보정 사항입니다.
