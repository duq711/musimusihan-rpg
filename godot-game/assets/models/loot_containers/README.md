# 루팅 컨테이너 모델

사용자 제공 Blender ZIP 4개에서 만든 게임용 GLB다. 원본·제작 스크립트·비교 렌더·독립 검증은 프로젝트 최상위 `asset-staging/loot_containers_20260912/`에 있다.

모든 모델은 Godot Y=0 바닥, XZ 중앙 원점, 전방 -Z다. 루트 `Body`와 실제 뚜껑인 `LidPivot/Lid`를 분리했다. `LidPivot/LidLeftContact`, `LidPivot/LidRightContact`는 실제 윗면 접점이다. 뚜껑 아래 잠금쇠가 있으면 함께 움직인다.

- `treasure_chest.glb`, `wooden_crate_01.glb`: 뒤쪽 +Z의 LidPivot, +X 68° 회전.
- `wooden_barrel_01.glb`, `wooden_crate_02.glb`: LidPivot을 위로 들고 뒤쪽 테두리에 걸쳐 놓는 게임 동작을 사용한다. extras `lift_distance_m=0.32`는 들어올리는 과정의 최고 높이다.
- `manifest.json`: 정확한 치수·bounds·접점·텍스처·삼각형 수·SHA-256.

2K 색/법선, 1K 거칠기/금속성 맵을 GLB에 내장했다. 애니메이션 클립은 없으며 실제 게임 루팅 진행도가 LidPivot을 제어한다.
