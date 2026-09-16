# 은신처 폐허 미술 목표

Codex의 내장 ImageGen을 사용해 2026-09-09에 생성한 8개 독립 이미지입니다. 각 방의 기존 게임 화면을 참조 이미지로 사용했습니다. 한 이미지에는 한 공간만 들어 있으며 콜라주가 아닙니다.

`generation_manifest.json`에는 각 이미지의 전체 프롬프트, 참조 스크린샷, 생성 원본 위치와 프로젝트 복사본 경로가 기록되어 있습니다. 생성 원본은 삭제하거나 덮어쓰지 않았습니다.

| 방 | 목표 파일 |
|---|---|
| 중앙 저수조 홀 | `concept_central.png` |
| 예배당 입구 | `concept_entrance.png` |
| 관리인 침실 | `concept_sleep.png` |
| 빈 저장고 | `concept_storage.png` |
| 작업실 | `concept_workshop.png` |
| 침수 저장고 | `concept_flooded_store.png` |
| 봉인된 납골실 | `concept_ossuary.png` |
| 배수로 | `concept_drain.png` |

게임은 이 그림을 배경으로 띄우지 않고 실제 3D 공간을 렌더링합니다. Blender 원본은 상위 프로젝트의 `asset-staging/hideout_ruins_blender/hideout_ruins_kit.blend`, 배치 모델은 `assets/3d/hideout_ruins/`에 있습니다.

비교 화면은 `artifacts/visual_qa/hideout_ruins/`에 반복별로 보존합니다. `scripts/hideout_ruin_views.gd`가 목표 생성, 실제 렌더러, 테스트룸의 공통 시점 목록입니다.

`surface_damp_limestone.png`는 방 이미지와 별도로 ImageGen에서 생성한 이음매 없는 젖은 석회암 표면입니다. 실제 석재 재질의 색과 미세 요철에 사용하며, 생성 프롬프트와 원본 경로는 `surface_generation_manifest.json`에 보존합니다.
