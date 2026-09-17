# 듬직한 팔과 손 · 2026-09-15

첨부 체형 참고에 맞춰 이전 버전보다 전완 약 38%, 위팔 약 26% 추가 확대. 손바닥·손가락·장갑은 30% 확대했습니다. 원본 SCN/GLB를 보존하고 공통 팔 어댑터에서 변형합니다. 손의 파지 중심은 유지하고 소매는 이동한 손목에 연결합니다.

- before_after.png: 왼쪽 직전 버전, 오른쪽 이번 버전. 동일 카메라·시간.
- heavy_arms_splint.gif: 현재 부목 전체 동작.
- equipment_contact_sheet.png: 검·방패·활·횃불·펴진 손 등 8자세.
- tests.log: supplied_fp_arms, splint_motion 통과. 손목 간격 0, 최대 프레임 이동 0.0272m.
- capture.log, equipment_capture.log, manifest.json: 실제 Vulkan/embedded 렌더, 원정·커서·촬영 소스 보존.

기존 부목 붕대의 들뜸은 별도 보정 사항입니다. 모든 손가락과 장비 표면의 접촉을 수치 검증한 것은 아닙니다.
