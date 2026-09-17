# 1인칭 내리찍기 미리보기

Godot 프로젝트 관리자에서 이 폴더의 `project.godot`을 가져온 뒤 **실행(F5)** 하세요. 처음에는 GLB와 텍스처 가져오기가 진행됩니다. 내리찍기는 원래 속도 **1.55초**로 한 번 재생되며, **Space** 또는 **Replay** 버튼으로 다시 재생합니다.

필요한 모델은 `assets/Overhead_Final.glb`입니다. 전체 계층·검·장갑·방패·7개 뼈·스킨 메시를 포함한 파일을 그대로 사용합니다. 이 프로젝트는 별도의 미리보기이며 기존 게임 프로젝트를 변경하지 않습니다.

카메라는 위치·회전 기본값, 세로 FOV 76°, near 0.025m입니다. GLB를 카메라의 자식으로 그대로 붙이고, 원본 정규화나 팔 변환을 다시 적용하지 않습니다.

자동 검사 예시:

```text
Godot --headless --editor --path . --import
Godot --headless --path . -- --verify-preview --report ABSOLUTE_REPORT_PATH.json
```

자동 검사는 PackedScene 가져오기와 원래 속도 1회 재생, 스킨 뼈 갱신, 완료 신호를 확인합니다. 화면 품질이나 Mac의 실제 게임 연결 확인은 별도입니다.
