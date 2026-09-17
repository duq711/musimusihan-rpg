# 불규칙한 육포 3D 에셋

첨부한 `beef-jerky.sbsar`와 육포 사진을 바탕으로 제작한 8종입니다. 길이·폭·두께·찢어진 끝·뒤틀림이 서로 다릅니다. 단위는 미터이며 개별 조각의 길이는 약 7–18.5cm입니다.

## 파일

- `beef_jerky.blend`: 편집 가능한 8종, 별도 묶음 컬렉션, 미리보기 조명·카메라. 텍스처 내장.
- `beef_jerky_pile.glb`: 중력 시뮬레이션으로 안정적으로 겹쳐 놓은 8조각 묶음. 배경·카메라·조명 없음.
- `beef_jerky_variants.glb`: 서로 떨어뜨려 배치한 8종. 각각 별도 이름을 가진 메시.
- `individual/`: 원점에 배치한 개별 GLB 8개. 소품·손에 쥐는 모델로 사용 가능.
- `textures/`: 첨부 SBSAR에서 변환한 2048×2048 색상·OpenGL 노멀·거칠기·금속성·16비트 높이 맵.
- `jerky_pile.png`, `jerky_variants.png`: 위 모델의 실제 Blender Cycles 렌더.
- `asset_manifest.json`: 원본 SHA-256, 실제 크기, 정점·삼각형 수, 닫힌 메시 부피.

개별 조각은 2,730정점 / 5,456삼각형, 8종 묶음은 43,648삼각형입니다. 하나의 PBR 재질을 공유합니다. 높이 정보는 메시의 미세한 표면 변화에도 반영했습니다. 각 조각의 아래쪽은 별도의 UV 구간을 사용하며 단면까지 닫힌 메시입니다.

## 원본과 제작

- 원본: `/Users/duq711gmail.com/Downloads/beef-jerky.sbsar` (변경 없음)
- SBSAR 그래프: `pkg://Beef_Jerky`, 원본 작성자 메타데이터: `danie`
- Adobe 공식 Substance Integration Tools를 작업 폴더에 풀어 PNG를 변환했습니다. Blender 환경에 추가 기능을 설치하거나 사용자 설정을 변경하지 않았습니다.
- 변환 코드: `../../asset-staging/beef_jerky_20260916/render_substance.py`
- 최종 묶음 미리보기 코드: `../../asset-staging/beef_jerky_20260916/render_final_pile.py`
- 모델 제작 코드: `../../asset-staging/beef_jerky_20260916/build_jerky.py`
- 제작: Mac / Blender 5.2.1 LTS. 색상 맵은 sRGB, 데이터 맵은 Linear, 노멀은 OpenGL입니다.

변환 도구의 공식 배포처: [Adobe Substance in Blender 설치 안내](https://experienceleague.adobe.com/en/docs/substance-3d/ecosystem/3d-applications/blender/downloading-and-installing-the-plugin).

## 게임에서 보기

`F2 → 기본 → 육포 외형 · 불규칙한 8종`

쌓인 묶음을 먼저 표시합니다. 도감 목록에서 펼친 8종 또는 개별 조각을 선택하고 6방향으로 살펴볼 수 있습니다. `F2`·`Esc`·복귀 버튼으로 돌아갑니다. 이번 제작 범위는 3D 외형이며, 먹는 애니메이션과 음식 효과는 포함하지 않습니다.

게임 파일은 `../../godot-game/assets/3d/items/beef_jerky/`에 있습니다. 개별 모델도 같은 GLB에서 해당 메시를 꺼내 사용하므로 게임 폴더에 텍스처를 8번 복제하지 않습니다.

## 검증 결과

최종 육포 10개 도감 항목의 실제 메시·재질·카메라·테스트룸 반복 진입/복귀·초기화·원정 복원 시험을 통과했습니다. 실제 Godot Vulkan 렌더러에서 60장을 촬영했고 소스 모델 해시와 이미지 해시를 확인했습니다. [게임 검증 기록](../../godot-game/assets/3d/items/beef_jerky/README.md)을 참고하세요.
