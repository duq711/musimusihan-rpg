# iteration_07 연속 소매의 Godot 연결 설계

2026-09-10. Windows 제작 코드의 읽기 전용 검토에 근거한 설계다. 이 문서를 만들 때 최종 GLB의 바인드·노드 변환을 직접 확인하지 않았다. 기존 게임 코드와 원본 에셋은 수정하지 않았다.

납품 대상은 overhead 1개, 1.55초다. root가 확인한 최종 GLB는 18,986,536 bytes, SHA-256 `a0df768367d78a487573101e780b881869b52b17ddd6daeaaea9cbcf6b24f319`이다. 이 값은 수신 후 로컬 파일과 독립 대조해야 한다.

## 제작 소스로 확인된 사실

근거 파일: `windows_final_source_changes.json`. `changes[3]`는 continuous_sleeve.py 최초 전체 코드이고, `changes[7]`은 최종 반경 및 부착물 스킨 변경이다. 아래 행 번호는 각 항목의 `diff.text` 내부 행 번호다.

- `changes[3]:18–24`: 본은 SleeveHand, SleeveWrist, SleeveForearm, SleeveElbow25, SleeveElbow50, SleeveElbow75, SleeveUpper. 모두 부모 없는 독립 본이며 Blender edit head=(0,0,0), tail=(0,.1,0)이다. 코드상 Blender 바인드 basis는 identity다. glTF/Godot의 실제 바인드가 identity라는 뜻은 아니다.
- `changes[3]:9–17`: 기존 Forearm의 material_index=0 소매 면을 제거하고 가죽 끈·버클을 남긴다. 기존 UpperArm과 시험용 구형 관절 덮개는 제거한다. 검과 장갑은 이 함수의 변경 대상이 아니다.
- `changes[3]:31–58`: 새 연속 소매는 129개 단면 × 64 정점, 양 끝을 막은 표면이다. vertex weights는 손목에서 어깨로 향하는 축 위 거리에 따라 인접 본 둘 사이를 선형 보간한다. Armature preserve-volume은 false, 즉 선형 블렌드 스키닝이다.
- `changes[7]:8–21`: 남은 RightArm_Forearm_Surface와 RightArm_WristCuff_Surface에도 동일한 가중치와 Armature modifier를 적용한다. 실제 적용 대상은 RightArm_ContinuousSleeve_Surface 및 이 두 부착물, 총 세 스킨 메시다. 커프를 기존 rigid fit_arm 방식으로 따로 움직이면 최종 결과와 달라진다.
- `changes[3]:62–87`: 187개, 120 Hz 평가 시각에서 일곱 본의 TRS 키를 생성한다. quaternion 부호 연속성을 맞추고 FCurve는 LINEAR다. 이 코드는 Godot 카메라 공간의 제어 행렬에서 본 키를 계산한다.
- `changes[2]:119–130`, `changes[4]:23–31`: 최종화는 제어 노드와 새 Armature를 함께 export 대상으로 다루고 SKIN일 때 export_skins를 켠다. export_yup=true이므로 실제 GLB 축 변환 확인이 필요하다.

## 현재 게임의 팔 계산과 대응

`sword_long_grip_visual.gd:84–140`의 fit_arm과 _fit_segment를 재사용할 수 있다. `player.gd`의 _fit_sword_grip는 이미 최종 검 pivot이 적용된 후 실제 shoulder/elbow를 이 함수에 전달한다. 새 소매도 같은 호출에서 계산된 관절을 받아야 하며 독립 타이머·별도 IK를 두지 않는다.

기호:

- T: 최종 weapon_pivot의 camera-local Transform3D. 공격, 이동, 조준, 충돌 복귀 등 최종 합성이 끝난 값.
- W0/E0/H0: SwordLongGripVisual.REST_WRIST / REST_ELBOW / REST_SHOULDER. **원본 SOURCE_READY 역변환으로 정규화한 검 공간**이다.
- e = inverse(T) * E_camera, h = inverse(T) * H_camera. 고정 손목은 W0이다.
- FF = fit_segment(W0,E0,W0,e), FU = fit_segment(E0,H0,e,h).
- qF/qU: 각각 FF/FU의 회전. 단위 길이 구간에서는 정확한 회전 basis다. 실제 납품에 축척이 있으면 아래 TRS 검증이 필요하다.

정규화된 검 공간에서의 바람직한 스킨 **변형 행렬 D**는 다음과 같다.

| 본 | 회전 R | translation |
|---|---|---|
| SleeveHand | I | (0,0,0) |
| SleeveForearm | FF.basis | FF.origin |
| SleeveUpper | FU.basis | FU.origin |
| SleeveWrist | Basis(slerp(I,qF,0.5)) | W0 - R*W0 |
| SleeveElbow25 | Basis(slerp(qF,qU,0.25)) | e - R*E0 |
| SleeveElbow50 | Basis(slerp(qF,qU,0.50)) | e - R*E0 |
| SleeveElbow75 | Basis(slerp(qF,qU,0.75)) | e - R*E0 |

이는 `changes[3]:66–71`의 Windows 정의에서 T를 왼쪽으로 제거한 식이다. 실제 Windows 값은 Hand=T, Forearm=T*FF, Upper=T*FU이고 중간 본은 camera-space e/w를 고정한다. T가 단위 축척의 강체 변환이면 공통 회전을 제거해도 slerp 결과가 같다. 이전 rigid cuff의 qF 100% 회전을 SleeveWrist에 쓰면 안 된다.

이 식은 본 pose 그 자체가 아니라 **bind 상태 정점에 작용할 deformation**이다. 본 pose를 무조건 D로 설정하면 glTF 바인드가 남아 있을 때 이중 변환된다.

## 권장 최소 adapter 경계

1. 원본 SwordHold_Static.glb는 보존하고 최종 GLB를 새 경로에 설치한다. 새 GLB의 Skeleton+Skin+세 메시 리소스를 보존해 인스턴스화한다. 스킨을 일반 정적 _bake_mesh 경로에 통과시키지 않는다.
2. 실제 import 트리에서 세 메시 및 Skeleton을 찾고, 숨긴 애니메이션 제어 노드의 부모 변환까지 먼저 계산한다. 필요한 트리를 유지하거나 재부모화 전후 전역 변환을 보존한다. 이름만 골라 transform=I로 재부모화하지 않는다.
3. adapter는 weapon_pivot 아래에서 canonical bind 공간을 표현한다. 노드·정점 축 변환을 한 번만 적용한다. CameraSpace의 Blender↔Godot 축 회전, SOURCE_READY, SwordGrip의 첫 키를 임의로 중복 제거하지 않는다.
4. 기존 정적 오른쪽 소매 세 부분만 숨긴다. 원본 장갑·검은 계속 사용한다. 새 GLB 속 검·장갑·방패·카메라·제어 시각화는 중복 렌더하지 않는다. 새 skin 세 메시도 rigid Forearm/Cuff 노드의 변환을 추가로 받지 않는다.
5. adapter의 fit 호출은 기존 _fit_sword_grip와 같은 최종 관절·검 pivot을 사용한다. 첫 import 때 본 이름/바인드/mesh 목록을 캐시하고 프레임마다 7개 행렬만 갱신한다. AnimationPlayer 자동 재생이나 SkeletonModifier가 이 값을 나중에 덮지 않도록 소유권을 하나로 둔다.
6. viewmodel renderer의 레이어·깊이 처리·가시성 관리에 새 메시를 포함한다. 최초 setup 이후 attach하면 등록을 갱신해야 하는지 실제 renderer를 확인한다. 장비 전환·상자 수납 때 기존 weapon arm과 함께 숨고 복원되어야 한다.

## 실제 GLB로 결정할 바인드 변환

먼저 raw glTF의 scene/node matrix, skin.joints, inverseBindMatrices, 각 mesh node transform, joint 부모, JOINTS_0/WEIGHTS_0를 읽는다. Godot import 후 Skeleton의 global rest와 Skin의 bind 이름/행렬이 무엇으로 바뀌었는지 대조한다. 슬롯 순서는 이름으로 매핑하며 코드의 bone_defs 순서와 같다고 가정하지 않는다.

canonical 정점 p를 skeleton 공간의 bind 정점으로 보내는 행렬을 A라고 정의하면, 원하는 skeleton 공간 변형은 D_s = A*D*inverse(A)다. 실제 Skin이 사용하는 inverse bind를 I_b라고 할 때, 동일한 공간에 있는 desired global bone pose는 P_b = D_s*inverse(I_b)여야 한다. I_b가 global rest R_b의 역행렬임을 확인한 경우 P_b = D_s*R_b로 단순화된다. mesh-to-skeleton 보정이 Skin bind에 포함된 경우에도 항의 공간을 먼저 일치시켜야 한다.

`Skeleton3D.set_bone_global_pose`의 global은 월드가 아니라 Skeleton 기준이다. 부모가 생긴 import라면 필요한 local pose는 inverse(P_parent)*P_b다. 별도 rest 곱을 중복하지 않는다. [Godot 공식 Skeleton3D 문서](https://docs.godotengine.org/en/stable/classes/class_skeleton3d.html)를 확인했다.

## 수신 뒤 필요한 검증

2026-09-10 추가: 실제 metadata 패킷의 `reports/godot_runtime_summary.json`은 Godot GLTFDocument로 읽은 세 스킨의 정점 버퍼가 이미 canonical 좌표이고, rigid-node의 C 보정을 스킨 행렬에 적용하지 않았다고 기록한다. 이 경우 스킨 식은 `K * P_b * I_b * p = D_b * p`이며 adapter가 설정할 pose는 **`P_b = inverse(K) * D_b * inverse(I_b)`**다. K는 adapter 아래 Skeleton의 고정 프레임이다. 여기서는 우측 K를 추가로 곱하지 않는다. 현재 adapter 초안은 이 표현을 사용하며 실제 Mac 리소스 importer가 같은 정점 공간을 유지하는지 최종 GLB의 native 재생 비교로 확인해야 한다. 임포트의 첫 animated pose를 inverse bind 대신 쓰지 않는다.

- 수신 GLB 크기/SHA, skin=1/본=7/skin mesh=3, 누락/중복 본, finite TRS, 정규화 weight 합, 예상 skin bind와 canonical wrist/elbow 좌표를 확인한다.
- source_samples의 실제 e/h로 계산한 FF/FU와 납품 parts_camera를 비교한다. Windows는 본 값을 Matrix.decompose→TRS로 키 저장한다. FF에 비단위 축척·shear가 있으면 raw FF 행렬 그대로 적용한 결과와 달라질 수 있다. 실제 키에서 차이를 측정한 다음 필요할 때에만 Windows와 같은 회전/축척 분해를 재현한다.
- 중립, 준비 최고점, hit, 최대 팔꿈치 굽힘, 회수 끝 등 실제 키에서 imported animation의 7개 bone skin matrices와 adapter 출력을 비교한다. animation은 비교용으로만 평가하며 production timer를 별도로 돌리지 않는다.
- 실제 세 메시의 weight를 적용해 동일 정점의 CPU LBS 위치를 비교한다. 관절 점만 같아도 cuff/strap 표면이 다를 수 있다. Hand가 장갑과 움직임을 공유하고 Wrist/Elbow 중간 본이 각 고정점을 보존하는지 함께 확인한다.
- 최종 합성 overlay, 공격 진입 t=0, guard·clash 복귀, pause, 장비/수납 복원에서 팔 표면이 한 프레임 뒤따르거나 이전 skin pose를 남기지 않는지 실제 player 테스트에 포함한다.
- 시각 검토는 연속 소매와 커프/끈의 틈·겹침, 최대 굽힘 안쪽의 찌그러짐, 뒷면 노출, 카메라 프레이밍을 실제 Godot 렌더에서 확인한다. LBS 관절 계산이나 headless 성공만으로 틈 문제가 해결됐다고 단정하지 않는다.

현재 단계에서는 이 adapter의 실행 코드나 샘플을 생성하지 않는다. 실제 GLB 바인드가 확인되면 위 식의 A/I_b를 확정한 다음 독립 helper로 구현할 수 있다.
