# 내리찍기 최종 에셋 — Overhead Final

승인된 1.55초 내리찍기 경로와 검·장갑의 파지를 유지하면서, 팔꿈치·손목을 연속된 소매로 마감한 1인칭 에셋입니다. 이번 묶음은 내리찍기 한 동작입니다.

## 바로 확인하기

- `Media/Overhead_Final_60fps.mp4`: 1280×720, 60fps, 원래 속도 1.55초.
- `Media/Overhead_Final_Loop_60fps.mp4`: 같은 동작을 3번 재생하는 4.65초 미리보기.
- `GodotPreview/project.godot`: Godot에서 Import한 뒤 F6 또는 F5로 실행합니다. 자동으로 한 번 재생하며 Space로 다시 재생합니다.
- `GodotPreview/assets/Overhead_Final.glb`: 게임에 가져갈 실제 애니메이션 모델.
- `Blender/Overhead_Final.blend`: 텍스처를 포함한 편집용 Blender 파일.

## 적용 기준

GLB 전체 계층과 포함된 `overhead` 애니메이션을 사용합니다. 카메라 로컬 좌표계의 미터 단위이며, 예제는 Camera3D 아래에 그대로 넣습니다. 기본 검토 카메라는 세로 FOV 76도, 16:9, near 0.025m입니다. 위치·회전에 추가 ready 보정을 중복 적용하지 않습니다.

최종 소매는 1개 Skin·7개 bone·3개 skinned mesh로 변형됩니다. 기존 Shoulder_R/Elbow_R/Wrist_R 등 8개 동작 컨트롤은 유지했습니다. `Animation/arm_pose_samples.json`은 그 8개 컨트롤의 187개·120Hz 기록이며, 이 JSON의 부품 행렬만 재생해서는 최종 소매 변형을 재현할 수 없습니다. **GLB의 Skeleton/Skin/AnimationPlayer도 함께 가져와야 합니다.**

방패의 RearGrip, RearGripTop, RearGripBottom, RearArmStrap을 복원했습니다. 왼팔·몸통은 이 1인칭 오른팔 에셋에 포함하지 않습니다. 닫힌 어깨 끝은 카메라 밖에서 사용하는 마감이며, 전신 캐릭터의 어깨 스킨 접합은 별도입니다.

편집본 일부 custom property에는 초안 단계의 `no_skin`/`review` 표기가 남아 있습니다. 최종 구조는 위의 1 Skin·7 bone이며, 실제 GLB와 검증 보고서가 기준입니다. 이전 검토용 파일 이름을 최종 배포 이름으로 변경했으며 파일 내용은 검증된 iteration_07과 같습니다.

## 검증

Blender에 GLB를 새로 가져와 187개 시각에서 실제 변형된 소매·끈·커프 정점을 비교했습니다. 최대 차이는 약 0.000000456m이며, 검·장갑 파지와 4개 방패 연결점도 보존됐습니다. Godot 4.7.2에서 실제 가져오기와 애니메이션 재생, bone/bind/weight에 따른 스키닝을 확인했습니다. 영상은 Blender Cycles에서 렌더링했으며 Godot 화면 캡처가 아닙니다.

이 묶음은 독립 에셋과 미리보기 프로젝트입니다. Mac의 실제 게임 프로젝트에는 아직 설치하지 않았습니다. 게임의 공격 판정·피해량·입력 연결은 이 미리보기에서 변경하지 않습니다.
