# 불규칙한 육포 에셋

제공된 `beef-jerky.sbsar`에서 변환한 2K 색상·OpenGL 노멀·거칠기·금속성 재질을 사용합니다. 원본 파일은 변경하지 않았습니다.

- `beef_jerky_variants.glb`: 각각 별도 메시인 8조각. 미터 단위, 약 7–18.5cm 길이, 조각당 5,456삼각형.
- `beef_jerky_pile.glb`: 같은 8종을 Blender 강체 시뮬레이션으로 바닥에 내려놓은 배치.
- `*_jerky_*.png`: Godot이 GLB에서 추출한 재질 맵.
- 제작 원본과 개별 GLB: `../../../../../exports/Beef_Jerky_2026-09-16/`

## 시험

`F2 → 기본 → 육포 외형 · 불규칙한 8종`에서 실행합니다. 목록으로 묶음·8종 펼친 모습·개별 조각을 선택할 수 있습니다. 음식 효과·먹기 모션은 이번 에셋 제작 범위에 포함되지 않습니다.

2026-09-16 검증:

- `dark_fantasy_gallery_test.gd`, 육포 관련 10개 항목: PASS. 실제 메시 수·두께·미터 단위·UV·색상/노멀/거칠기 맵·6방향 범위·실행 항목·반복 F2/복귀·초기화·원정 복원.
- Mac 숨김 Vulkan 렌더: 10개 항목 × 6방향 = 60장. 소스 GLB 및 이미지 해시 일치, 원정·커서 보존.
- 결과: `../../../../artifacts/visual_qa/dark_fantasy_objects/beef_jerky_20260916_final/`.
- Blender에서 8종 모두 닫힌 메시와 양의 부피 확인. 최종 10개 배포 GLB에 UV·노멀·탄젠트·PBR 이미지 내장 확인.

가져오기는 새 육포 파일만 포함한 프로젝트에서 같은 `res://assets/3d/items/beef_jerky/` 경로와 공유 가져오기 캐시를 사용했습니다. 현재 캐시는 새 텍스처 UID를 경로로 해결하는 경고를 출력하지만 실제 재질 로드와 렌더 검증은 통과했습니다. 헤드리스 종료 로그에는 ObjectDB 2개 누수 경고도 남아 있습니다. 기록은 `../../../../../asset-staging/beef_jerky_20260916/test_final.log`와 `preview_final.log`에 보존합니다.
