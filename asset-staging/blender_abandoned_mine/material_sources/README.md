# 폐광 촬영 소재

Powered by [Poly Haven](https://polyhaven.com). 게임은 내려받은 로컬 파일만 사용하며 실행 중 외부 API에 접속하지 않습니다.

공식 출처에서 제공한 실제 표면 질감 5세트, 총 20장을 선택했습니다. 모든 배포 질감은 2048 × 2048이고 합계 약 39.93 MB입니다. 기존 게임 소재는 변경하지 않았습니다.

| 소재 ID / 공식 출처 | 용도 | 원본 한 타일의 실물 크기 | 제작자 |
|---|---|---|---|
| [rock_boulder_dry](https://polyhaven.com/a/rock_boulder_dry) | 밝은 회색·베이지색의 갈라진 암석 | 1.8 × 1.8m | Dimitrios Savva 촬영 / Rico Cilliers 가공 |
| [dark_rock_02](https://polyhaven.com/a/dark_rock_02) | 검은 층리와 큰 균열이 있는 암벽 | 약 2.001 × 2.001m | Amal Kumar |
| [brown_mud_rocks_01](https://polyhaven.com/a/brown_mud_rocks_01) | 습한 흙과 작은 자갈 | 약 1.3 × 1.3m | Rob Tuytel |
| [rough_wood](https://polyhaven.com/a/rough_wood) | 갈라진 오래된 갱목 | 0.5 × 0.5m | Rob Tuytel |
| [rust_coarse_01](https://polyhaven.com/a/rust_coarse_01) | 거칠게 부식된 철재 | 2.2 × 2.2m | Dimitrios Savva 촬영 / Rico Cilliers 가공 |

암석의 광물학적 종류를 별도로 검증하지 않았으므로 첫 소재를 석회암으로 단정하지 않습니다. `brown_mud_rocks_01`에는 작은 식물과 유기물이 일부 포함되어 있어 입구 주변의 습한 바닥에 잘 맞습니다. 빛이 없는 심층에서는 다른 암석 재질과 섞어 사용하고 자연광처럼 밝고 초록색으로 보이지 않도록 실제 조명 아래에서 확인합니다.

## 파일과 사용

게임용 질감은 `godot-game/assets/3d/abandoned_mine/textures/<소재ID>_<채널>_2k.jpg`에 있습니다. `godot-game/assets/3d/abandoned_mine/material_manifest.json`은 소재 ID, 용도, 공식 원본 주소·저작자·CC0 링크, 물리 크기, 채널별 경로와 파일 검증값을 기록합니다. 이 폴더의 동일한 manifest는 제작용 사본입니다.

| 채널 | Blender / Godot 설정 |
|---|---|
| `albedo` | Base Color / Albedo, sRGB. 직접 촬영 표면의 색을 사용하고 조명을 중복해서 굽지 않습니다. |
| `normal_gl` | Non-Color / 선형, tangent-space OpenGL +Y. Normal Map 노드에 연결하며 녹색 채널을 반전하지 않습니다. |
| `roughness` | Non-Color / 선형, 흰색은 거칠고 검은색은 매끈합니다. |
| `height` | Non-Color / 선형. JPEG 8비트 높이 자료이며 미세 요철 보조용입니다. 큰 균열·튀어나온 돌·실루엣은 메시로 만듭니다. |

공식 API `dimensions`의 단위는 mm이며 이를 m로 변환한 `physical_size_m`를 사용합니다. 예를 들어 1.8m 암석 타일을 18m 벽에 한 번만 늘이면 표면 크기가 10배가 됩니다. 세계 좌표 기반 매핑은 X/Y/Z를 실제 타일 길이로 나누고, UV 방식은 면의 실제 길이에 맞춰 반복합니다. 목재는 긴 나뭇결 방향과 기둥·보의 길이 방향을 맞춥니다.

Manifest의 `suggested_displacement_m`와 `suggested_metallic`은 제작 시작값이며 원본에서 측정한 값이 아닙니다. 녹이 대부분인 철은 비금속 표면처럼 반응하므로 전체를 metallic 1로 만들지 않습니다. 맨철이 닳아 드러난 부분은 별도 재질·마스크로 처리합니다. 젖은 곳은 원본 요철을 유지하며 국소적인 물막과 거칠기 변화로 표현합니다.

## 출처·검증·재현

[Poly Haven의 공식 라이선스](https://polyhaven.com/license)에 따라 모든 선택 소재는 **CC0 1.0**이며 상업적 사용과 게임 내 재배포가 허용됩니다. 법적 문서는 [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/)에서 확인할 수 있습니다. 출처 표시 의무와 별개로 제작자와 원본 주소를 manifest에 보존했습니다. 수집 도구는 [공식 API 약관](https://github.com/Poly-Haven/Public-API/blob/master/ToS.md)을 따르며 이 문서와 실행 파일에 API 출처 표시를 포함합니다.

`*_metadata.json`은 공식 소재 정보이며 `*_files.json`은 공식 다운로드 주소·MD5·파일 크기 기록입니다. 후보를 조사하며 받은 파일 목록도 보존합니다. `originals/`에는 실제 선택한 20장의 공식 2K JPEG 원본만 보관합니다. 정상 파일은 재실행해도 다시 내려받지 않습니다.

`python3 asset-staging/blender_abandoned_mine/material_sources/fetch_materials.py`로 재현합니다. 다운로드는 공식 파일 크기·MD5와 일치하는지 확인합니다. 노멀·높이는 원본 바이트를 유지하고, 알베도·거칠기만 macOS `sips`의 JPEG 품질 88·90으로 용량을 줄입니다. 해상도·색·무늬는 편집하지 않습니다. 배포 파일은 다시 크기 확인과 SHA-256 계산을 거치며 총 40 MB 제한을 검사합니다.

이번 확인은 원본 라이선스·메타데이터·20개 파일의 무결성·2K 해상도와 알베도 이미지의 육안 검토입니다. Blender/Godot에서 적용한 재질·조명·매핑의 최종 모습은 별도 장면 렌더링으로 확인해야 합니다.

## 추가 암벽 형상 원본

반복되는 동일 실루엣을 피하기 위해 서로 다른 [Rock Face 01](https://polyhaven.com/a/rock_face_01)과 [Rock Face 02](https://polyhaven.com/a/rock_face_02)의 CC0 glTF 패키지도 제작용으로 보관했습니다. 두 모델은 Dario Barresi가 제작했으며 02에는 Rico Cilliers의 가공 작업이 포함되어 있습니다. 각각 20,174개와 29,566개 삼각형이며, 1K 텍스처·버퍼를 포함한 다운로드는 약 3.05 MB와 3.53 MB입니다. 원본 파일은 게임에 자동으로 배치하지 않았습니다.

- `rock_face_01_scan/rock_face_01_1k.gltf`
- `rock_face_02_scan/rock_face_02_1k.gltf`

각 폴더의 `source_manifest.json`에 공식 출처·CC0·저작자·의존 파일 SHA-256과 실제 정점에서 측정한 경계를 저장했습니다. 웹사이트의 원본 크기 표기와 glTF에 실제 포함된 정점 크기가 다르므로 배치할 때는 `measured_geometry`를 사용합니다.

| 모델 | 실제 glTF 크기 X × Y × Z | glTF 바닥 중앙 맞춤 이동량 X,Y,Z |
|---|---|---|
| Rock Face 01 | 4.954 × 3.564 × 3.827m | −0.343, +0.034, +1.552m |
| Rock Face 02 | 2.711 × 2.472 × 2.127m | +0.906, +0.140, +0.125m |

glTF는 +Y가 위쪽이며 별도 노드 변환이 없습니다. Blender에서는 `(x,y,z) → (x,−z,y)`로 변환됩니다. 두 암벽은 닫힌 바위 덩어리보다 열린 표면 패치에 가깝습니다. 면의 주 방향은 glTF의 +Z와 위쪽(+Y), Blender에서는 −Y와 +Z입니다. 암벽의 뒤쪽 경계는 다른 벽 안에 묻고 드러난 표면이 통로를 향하도록 회전합니다. 원본에 야외 지의류가 포함되므로 필요하면 확보한 동굴용 재질로 교체하고, 큰 형상은 유지하면서 복제마다 회전·크기·가림을 달리합니다. 세밀한 배치는 실제 렌더에서 확인합니다.

재현은 `python3 .../material_sources/fetch_rock_scan.py rock_face_01`, 같은 명령의 `rock_face_02`, 그리고 `python3 .../material_sources/inspect_rock_scans.py` 순서입니다. 두 수집 명령은 공식 glTF 의존 파일의 크기·MD5를 검증하고, 검사 명령은 실제 버퍼를 읽어 정점 경계·삼각형 면 방향을 계산합니다.
