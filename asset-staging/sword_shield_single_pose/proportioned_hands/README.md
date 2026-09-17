# 손가락 길이 교정용 원본 보존 staging

`source_corrected_arms/`는 좌우 정체성을 바로잡은 `../corrected_arms/`의 두 GLB 원본 사본입니다. 추가 80% 장갑 연장부 이전이며, 기존 짧은 손가락 장갑과 원래 피부를 함께 사용합니다.

`proportion_hands.py`를 Python 3로 실행하면 `left_arm.glb`, `right_arm.glb`, `preservation_report.json`을 재생성합니다. GLB 입출력만 수행하며 게임 파일 복사, Blender, Godot 실행은 하지 않습니다. GLB 입출력 보조 코드는 보존된 `../corrected_sword/correct_longsword.py`에서 읽습니다.

## 변형 및 보존 범위

- 실제 GLB joint의 로컬 +Y가 손가락 장축입니다. 네 손가락의 세 마디는 장축만 0.8배로 줄이고 child1·child2의 로컬 위치를 0.8배로 옮깁니다. 엄지 CMC·MCP 위치와 metacarpal은 보존하고 엄지1·2 마디 및 child2 위치만 같은 비율로 줄입니다.
- 정점은 원본 skin weights를 그대로 사용해 각 본의 원래 bind 좌표 → 로컬 Y 보정 → 새로운 rest 좌표 순서로 변환한 결과를 가중 합산합니다. 손 전체에 scale을 추가하지 않습니다. 손가락 순수 가중치 정점의 로컬 X·Z 단면을 보존합니다.
- 손목·네 MCP·엄지 CMC/MCP, 관절 회전·scale, 피부와 원래 장갑의 weights·UV·indices·materials, 기존 단단한 손목·소매·커프 메시를 보존합니다. 순수 wrist 정점은 좌표·법선·접선까지 원본 바이트 그대로입니다.
- 원본의 wrist/finger 혼합 가중치 연결부는 마디 길이 보정에 따라 최대 약 3.12mm 움직입니다. 이것은 전체 손바닥 축소가 아니며, 보고서에 해당 정점 수와 최대 이동을 따로 기록합니다.
- 새 rest 위치에 맞춰 inverse bind의 translation만 보정하며, 기존 basis와 순서는 보존합니다. 법선은 변형 Jacobian의 역전치, 접선은 변형 Jacobian으로 갱신합니다. 원본의 glTF float32 bind 오차를 새로 확대하지 않는지 재확인합니다.

`preservation_report.json`에 양손 입력/출력 SHA-256, 실제 관절 및 끝마디 피부 길이, 단면 오차, 메시 경계, 소매 보존 해시와 **저장한 float32 GLB를 다시 읽어 검증한 결과**가 있습니다. 좌우 손의 서로 다른 원본 가중치 및 꼭짓점 순서를 유지하므로 혼합 영역의 미세 차이를 억지로 대칭화하지 않습니다.

게임 반영·엔진 import·접촉 및 동작 검증은 root 작업에서 수행합니다. 이 staging의 수치 검증은 최종 화면이나 게임플레이 검증을 대신하지 않습니다.
