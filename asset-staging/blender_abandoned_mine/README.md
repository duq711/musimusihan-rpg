# 검은 물길 폐광 제작 자료

사용자가 제공한 1254 × 1254 폐광 지도의 배치를 가로 131m · 세로 139m 안에 추적하고 Blender에서 지형과 채굴 시설을 제작한 원본입니다. 실제 플레이 장면은 `godot-game/cave_dungeon.tscn`이며 게임 안에서는 기존 목적지 이름인 **검은 물길 동굴**을 유지합니다.

## 기준 데이터와 결과물

| 파일 | 역할 |
|---|---|
| `trace_layout.py` | 사용자가 제공한 지도에서 손으로 추적한 원래 이미지 좌표. X는 동쪽, Z는 남쪽이며 한 단위는 1m입니다. |
| `layout.json` | 18개 비정형 공동, 31개 다중 굴곡 경로, 6개 수면, 7개 암석섬, 다리·채굴 시설·거수 유골과 실제 적·함정·상자 배치의 공통 원본. |
| `layout_trace.png` | 원본 지도와 방향·비율을 비교하기 위한 설계 도식. 게임 화면이나 렌더 이미지가 아닙니다. |
| `validate_layout.py` | 닫힌 방 다각형, 내부 진입 위치, 연결 그래프, 경로와 암석섬·기둥 사이 여유, 실제 게임 대상 위치 검사. |
| `generate_terrain.py` | 지도의 연결된 공간과 암석섬 높이를 입체 지형으로 만들고 Blender용 `terrain_mesh.npz`, 측정 자료와 보고서를 저장합니다. |
| `build_mine.py` | Blender 안에서 최종 지형·촬영 표면 재질·암벽 형상·지질·채굴 시설·소품·수면·등불을 구성하고 glTF로 내보냅니다. |
| `polish_export.py` / `scene_polish.py` / `finish_mine.py` | 전체 제작과 기존 원본 수정에 같은 마무리 순서를 적용합니다. 지형 정리 → 소품 접촉 → 암석 세부 → 암석 정점 접촉 → 면 내부와 광물 뿌리 접촉 → 연속 지질 재질 → 내보내기 면 정리를 거쳐 `.blend`·GLB·등불·충돌 기록을 함께 갱신합니다. |
| `surface_contact.py` | 촬영 암석 조각 132개의 정점을 실제 암벽에 맞추고 가장자리를 묻습니다. 변형 전 UV를 늘리지 않고 접한 지형과 같은 미터 단위 재질·연속 지질 색상을 사용합니다. |
| `formation_contact.py` | 암석 패치의 모든 면 중심·변 중간점을 검사해 허공을 가로지르는 면을 제거하고 새 경계를 묻습니다. 합쳐진 광물 메시도 성분별로 나눠 석순·종유석·파편의 실제 지지면에 뿌리를 맞춥니다. |
| `prop_contact.py` | 실제 메시를 측정해 소품 41개의 바닥 접촉, 지지대 5개의 발·천장 받침, 벽등 52개의 받침판·걸쇠·광원·충돌을 맞춥니다. |
| `rock_detail.py` | 촬영 암벽과 광물학적 균열·박리·유석 등 세부 형상을 최종 장면에 배치합니다. |
| `geology_materials.py` | 넓게 이어지는 광물 색·습한 흙 반점과 독립된 바닥/암벽 면 색상을 만듭니다. 암석은 1.8m 균열 사진과 강한 요철, 흙은 0.82m 입자 사진·약한 요철·높은 거칠기로 구분하며 glTF 면 모서리 색상으로 전달합니다. |
| `audit_export.py` | 내보낸 GLB의 내장 이미지, UV·노멀·촬영 재질, 필수 메시 이름, 부지 크기 기록과 원본 연결을 검사하고 SHA-256을 기록합니다. |
| `mine_props.py` / `bone_props.py` | 갱목, 작업대, 권양기, 창고, 성소, 다리와 형태를 갖춘 거수 유골 제작 모듈. |
| `blackwater_abandoned_mine.blend` | 최종 Blender 원본. 표면 텍스처를 포함해 저장하며 이 파일이 시각 검토와 수정의 출발점입니다. |
| `build_report.json` / `terrain_report.json` | 실제 생성된 지형·소품·등불 수와 제작 설정, 측정 결과. |
| `material_sources/` | 표면 촬영 자료와 암벽 스캔 원본, 공식 출처·제작자·파일 무결성 기록. 자세한 내용은 해당 폴더의 README를 참고합니다. |
| `previous_prototype/` | 이전 Godot 원형 공동·절차적 재질의 제작 이력 보관본. 현재 플레이 장면은 이를 사용하지 않습니다. |

게임용 결과는 `godot-game/assets/3d/abandoned_mine/`에 저장합니다. `abandoned_mine.glb`는 실제 환경 모델, `build_manifest.json`은 등불·소품 기록, `terrain_samples.bin`은 바닥·천장·공간 경계 측정값입니다. 이 폴더의 `layout.json`은 제작용 사본과 바이트 단위로 같아야 합니다. `cave_layout.gd`는 JSON을 Godot의 다각형·경로·위치로 변환하고, `cave_geometry.gd`는 Blender 메시와 충돌을 불러옵니다.

암석섬은 높이를 가진 바위입니다. 중앙의 거대 암석은 9.2m, 물속 작은 암석섬은 약 1~2.4m로 지정되어 있습니다. 천장까지 같은 높이의 기둥으로 바꾸지 않습니다. 수면은 얕은 보행 구역 위의 물 연출이며 수영·잠수 기능은 없습니다.

## 재현

아래 명령은 프로젝트 최상위 폴더에서 실행합니다. 지형 도구에는 Python 3.12와 `requirements-terrain.txt`의 패키지를 사용합니다. 현재 Codex의 Python은 다음 경로입니다. 다른 컴퓨터에서는 같은 Python 버전의 실행 파일로 바꿉니다. 시스템의 Python 3.9와 Python 3.12용 수치 계산 모듈을 섞지 않습니다.

```bash
MINE_PYTHON="/Users/duq711gmail.com/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3"
MINE_BLENDER="/Applications/Blender.app/Contents/MacOS/Blender"
"$MINE_PYTHON" -m pip install --target /tmp/mine-build-deps -r asset-staging/blender_abandoned_mine/requirements-terrain.txt
"$MINE_PYTHON" asset-staging/blender_abandoned_mine/trace_layout.py
"$MINE_PYTHON" asset-staging/blender_abandoned_mine/validate_layout.py
MINE_BUILD_DEPS=/tmp/mine-build-deps "$MINE_PYTHON" asset-staging/blender_abandoned_mine/generate_terrain.py
/usr/bin/nice -n 10 "$MINE_BLENDER" --background --factory-startup --threads 2 --python-exit-code 1 --python asset-staging/blender_abandoned_mine/build_mine.py
/usr/bin/nice -n 10 "$MINE_BLENDER" --background --factory-startup --threads 2 --python-exit-code 1 --python asset-staging/blender_abandoned_mine/polish_export.py
"$MINE_PYTHON" asset-staging/blender_abandoned_mine/audit_export.py
```

`build_mine.py`와 `polish_export.py`는 모두 `scene_polish.py`의 같은 마무리를 실행하므로 전체 재제작에서도 접촉 수정이 유지됩니다. 기존 `.blend`만 손볼 때는 `polish_export.py`를 실행합니다. 원본 `.blend`와 게임용 GLB, 등불·충돌 메타데이터가 함께 갱신됩니다. 통로에 걸린 등불은 표시나 충돌을 끄지 않고 실제 암벽에 고정하여 통행 공간을 확보합니다. `audit_export.py`는 Blender나 Godot 창 없이 내보내기 구조와 파일 연결을 점검하며 결과를 `export_audit.json`에 저장합니다. 실제 통행·바닥·천장은 이후 Godot 헤드리스 물리 검증으로 확인합니다.

기본 입체 지형 표본 간격은 `generate_terrain.py`의 `MINE_VOXEL_SIZE` 값입니다. 이 값을 바꾸면 충돌·실루엣·파일 크기와 제작 시간이 달라지므로 같은 조건으로 비교할 때 유지합니다. 다운로드한 표면 자료는 재사용합니다. 파일이 없는 환경에서 원본을 다시 받는 절차와 검증은 `material_sources/README.md`에 있습니다.

Godot에 새로운 GLB를 처음 가져올 때는 편집기의 리소스 가져오기가 한 번 필요합니다. 창을 열지 않는 가져오기와 자동 검증은 다음과 같습니다.

```bash
/usr/bin/nice -n 10 "/Users/duq711gmail.com/Desktop/Godot.app/Contents/MacOS/Godot" --headless --editor --path godot-game --import
godot-game/tests/run_headless_tests.sh cave_layout cave_geometry cave_dungeon cave_flow cave_preview test_room_session test_room
```

일반 검증은 지정된 헤드리스 실행기를 사용합니다. 사용자가 기존에 열어 둔 Godot이나 Blender 창은 조작하지 않습니다. 모델 원본의 배경 제작과 렌더에도 창·포커스·마우스 캡처를 사용하지 않습니다.

## 실제 기능과 시험

적 6명, 룬 함정 4개, 전리품 상자 5개는 `layout.json`의 `gameplay` 위치에서 실제 기존 전투·조사·수색 코드를 사용합니다. 일반 입장은 남쪽 갱도이고 모든 감시자를 처치한 뒤 북동쪽 기둥 성소에서 귀환합니다. 사망·생환 후 R로 재시작하면 같은 폐광의 남쪽 진입 지점으로 돌아갑니다.

테스트룸의 장면 탭은 전체 폐광과 일곱 주요 공동 직접 방문을 제공합니다. 지정 공동은 시험 세션의 일회성 입장 위치로만 쓰며 인벤토리나 원정 스냅샷에 추가하지 않습니다. F2 복귀, 재선택, 초기화, 사망 후 재시험과 메인 메뉴에서 원래 원정 복원을 자동 검증합니다.

검증은 원본 JSON 사본 일치, 다각형·경로 연결, 실제 Blender 메시 충돌, 0.5m 간격 캐릭터 크기 통행 검사, 바닥·천장·외벽, 실제 전투·상자·함정·귀환, 시험 세션 격리와 복원을 포함합니다. 통로의 바닥 검사는 부지 아래의 예비 바닥에 닿는 것으로 통과시키지 않습니다.

## 시각 검토 자료

새 폐광의 Blender 렌더와 검토 자료는 `godot-game/artifacts/visual_qa/abandoned_mine/`에 저장합니다. 최종 `.blend`의 실제 메시와 재질을 사용한 Blender 렌더이며 Godot 화면 캡처와 구분합니다. `mine_props_closeup.blend`와 `mine_props_closeup.png`는 유골·채굴 장치 등 소품을 별도로 살피는 제작 자료입니다.

Godot의 `tests/cave_preview.gd`는 게임 캐릭터·소리·원정 변경 없이 실제 지형, 동굴과 같은 환경, 휴대 횃불을 포함한 다섯 카메라를 만듭니다. 헤드리스 `cave_preview_test.gd`는 구성과 상태 격리만 확인하며 픽셀 검증을 주장하지 않습니다. 실제 macOS Godot 렌더러 창은 포커스를 가져갈 수 있으므로 숨김·비활성 실행이 검증되지 않았다면 기존 프로젝트 지침에 따라 먼저 사용자에게 실행 영향을 알리고 확인받습니다.

이전 `godot-game/artifacts/visual_qa/cave_offline/` 이미지는 제작 이력이며 새 모델을 보여 주는 자료로 사용하지 않습니다.

2026-09-05 접촉 수정의 최종 실제 Godot 화면은 `godot-game/artifacts/visual_qa/abandoned_mine/contact/`의 PNG 5개입니다. `cave_surface_contact_test.gd`는 가져온 암석 정점 8,797개와 소품·지지대·벽등을 실제 지형 충돌로 확인합니다. 테스트룸의 **벽 접근 · 무기와 방패 표시**, **폐광 · 입구 소품과 지지대**에서 실제 플레이 상태로 재시험할 수 있습니다. 검토 화면의 장비는 게임과 같은 별도 깊이 렌더링과 횃불 광원을 사용하며, 벽 근접 두 화면은 검정 실루엣을 검출하는 픽셀 검사도 통과했습니다.

2026-09-05 후속 자연화 수정에는 광물 뿌리와 암석 면 내부 검사, 흙·암석 재질 구분, 실제 발걸음 파동을 포함합니다. 최종 시각 자료는 `godot-game/artifacts/visual_qa/abandoned_mine/naturalism/`에 기록합니다. 원래 `Water_*`는 Blender 설계 위치이며 실제 게임 수면은 `cave_water.gd`가 같은 여섯 윤곽을 부드럽게 다듬은 촘촘한 메시로 만듭니다. 표면은 깊이에 따른 색·투과·잔물결·반사를 사용하며 보행 파동은 24개까지 보관하고 사라집니다. 이전 `contact/` 자료는 이번 암석 면 내부·물·재질 수정 전 검토 이력입니다.
