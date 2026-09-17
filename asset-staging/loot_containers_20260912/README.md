# 제공 상자 에셋의 Godot용 변환 — 2026-09-12

사용자가 제공한 ZIP 4개를 그대로 보존하고, 원본 메시와 PBR 맵을 사용하여 현재 Godot 프로젝트의 루팅 컨테이너 4종으로 변환했다. 공급 파일에는 모델·텍스처만 있었으며 내부 자료를 작업 지시로 실행하지 않았다. 출처와 무결성은 `source_manifest.json`에 기록했다.

실제 제작 호스트는 `gimjin-yeob-ui-MacBookAir.local` (Darwin ARM64), 실행기는 `/Applications/Blender.app/Contents/MacOS/Blender` 5.2.1 LTS다. 사용자의 최신 Mac 기본 지시를 적용했다. 실시간 MCP에 의존하지 않고 `--background --disable-autoexec --threads 2`와 낮은 우선순위로 변환·검증·CPU 렌더를 수행한다. 앱·게임·Terminal 창은 열지 않았다.

| 변형 | 실제 크기 X×Y×Z (m) | 삼각형 | GLB (MB, decimal) | 열기 |
|---|---|---:|---:|---|
| wooden_barrel_01 | 0.810 × 1.000 × 0.810 | 11,184 | 7.22 | 윗판 들어올리기 |
| treasure_chest | 1.200 × 0.774 × 0.654 | 31,997 | 12.52 | 뒤쪽 경첩, +X 68° |
| wooden_crate_01 | 1.100 × 0.466 × 0.545 | 6,576 | 9.14 | 뒤쪽 경첩, +X 68° |
| wooden_crate_02 | 1.280 × 0.509 × 0.581 | 5,176 | 8.53 | 윗판 들어올리기 |

게임 파일은 `godot-game/assets/models/loot_containers/`에 있고 정확한 크기·bounds·힌지 위치·접점·SHA-256은 그 폴더의 `manifest.json`을 따른다. 4K 원본은 `sources/`에, 2K/1K 파생 텍스처는 `runtime_textures/`에, 편집 가능한 정규화 파생 BLEND는 `normalized/`에 각각 보존한다. 모델들은 외부 텍스처 의존성이 없는 GLB다.

## 공통 런타임 규약

- Godot 좌표계의 바닥 Y=0, 수평 bounds 중심 XZ=0. 전면은 -Z다.
- 루트 아래 `Body`와 `LidPivot`을 분리한다. `LidPivot` 아래 실제 `Lid` 메시가 있고 필요한 잠금쇠도 함께 움직인다. 몸통 전체를 돌리지 않는다.
- `LidLeftContact` / `LidRightContact`는 모델 좌우를 기준으로 한 `LidPivot` 자식이며, 실제 뚜껑 윗면에 raycast한 제작 참고 접점이다. 현재 게임의 양손은 이 이름을 그대로 손 좌우에 대응시키지 않고, 앞·뒤·옆 접근에 맞춰 실제 삼각형의 위치와 법선을 계산한다. 모든 접점은 뚜껑 움직임을 따른다.
- root extras: `hinge_mode` (`hinge`/`lift`), `lid_open_degrees` (68), `lift_distance_m` (lift는 0.32), `asset_variant`.
- 분리형 뚜껑은 들어올린 후 뒤쪽 테두리에 걸쳐 놓는다. `lift_distance_m=0.32`는 에셋 제작의 상승 참고값이다. 현재 게임은 `sin(progress * PI) * 0.24`에 최종 지지 높이를 더하는 별도 상승 곡선을 사용하며, 최종 지지 높이는 몸통 테두리와 뚜껑 아랫면으로 계산한다. 최종 비교 자세는 `lid_rest_poses.json`을 따른다.
- 애니메이션 clip은 포함하지 않는다. 게임이 실제 루팅 진행도에 따라 `LidPivot`의 회전 또는 위치를 제어한다.
- treasure와 두 crate는 공급 원본에 독립 뚜껑 메시가 있었다. barrel은 원본의 윗판·손잡이 연결 컴포넌트만 분리하고 세로 판재·외부 테두리를 몸통에 남겼다. 이전 원본을 수정하지 않는다.
- treasure는 원본 103,330개 삼각형에서 31,997개로 줄였고, 나머지는 원본의 경량 구조를 유지한다. 모든 GLB 메시를 명시적으로 삼각화해 tangent와 normal map을 일치시킨다.
- Base color JPEG 2K, tangent normal PNG 2K/8bit, roughness·metallic PNG 1K/8bit. glTF는 roughness와 metallic을 PBR 텍스처로 패킹한다. 원본 EXR의 과도한 16bit PNG 용량을 런타임에 가져오지 않는다.

## 재현 및 검증

1. `scripts/inspect_sources.py`, `scripts/inspect_geometry.py`: 원본 오브젝트·재질·텍스처·연결 컴포넌트 구조 검사.
2. `scripts/build_assets.py`: 원본을 읽고 파생 텍스처·정규화 메시·뚜껑 hierarchy 작성.
3. `scripts/finalize_assets.py`: 런타임 비트 깊이/해상도 최적화, 삼각화, 실제 표면 접점, extras와 GLB 확정.
4. `scripts/render_and_validate.py`: 확정 GLB를 별도 빈 Blender 장면으로 다시 import하여 hierarchy·extras·PBR·tangent·텍스처 한계·원점·몸통 고정/뚜껑 움직임을 검사하고, 동일 스튜디오의 원본/런타임 닫힘/런타임 열림을 렌더.

`qa/`의 12개 이미지와 `validation_report.json`이 에셋 자체의 검증 근거다. 게임 기능의 실제 연결·테스트룸·세션 격리 검증은 통합 담당자의 게임 테스트 결과를 따른다. Blender 렌더를 Godot 화면 검증으로 주장하지 않는다.
