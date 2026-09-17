# 실제 Godot 방패 → Windows 제작 좌표 계약

작성: 2026-09-10. 정적 원본 GLB의 정점·노드와 현재 Godot 코드를 읽고 산술 계산했다. 새 애니메이션 제작·렌더·게임 코드 수정은 하지 않았다. 자세한 실제 값과 정점 index는 `SHIELD_CONSTANTS.json`에 있다.

**현재 Windows의 radius 0.32m disk 프록시와 실제 게임 ShieldPivot은 같은 대상이 아니다.** 실제 방패는 지름 약 0.854m이고 두께·손잡이·앞뒤 방향이 있다. 프록시의 pure translation을 production ShieldPivot 샘플로 이름만 바꾸면 안 된다. `shader_normalization_pending`도 해결된 것으로 표시하지 않는다. 실제 GLB를 가져와 재배치·회전·실루엣을 확인한 후 새 절대 피벗 값을 평가한다.

## 1. 원본과 구조

- Godot 경로: `godot-game/assets/3d/player/sword_shield/round_shield.glb`
- Windows 작업 폴더 내 경로: `work/game-project/RPG_Workspace/godot-game/assets/3d/player/sword_shield/round_shield.glb`
- SHA256: `8ca7482ae498083b426200cc8257e90e00d51a81ef6f08749c893ad3c59bdfe0`
- 크기: 2,799,680 bytes. 원본을 보존하고 별도 작업 파일에 import한다.
- 루트 `SwordsmanRoundShield` (node 5)와 메시 노드 `SwordsmanRoundShield_Surface` (node 4)는 모두 identity transform이다. 메시 1개/primitive 6개, node 6개, skin 0개, animation 0개다. mesh resource 이름 `Sphere.142`가 구형 프록시를 뜻하지는 않는다.
- 루트 자식은 위 메시 및 `RearArmStrap`, `RearGrip`, `RearGripBottom`, `RearGripTop`이다. 아래 marker 좌표는 루트 기준이며 별도 scale 보정은 없다.
- 표면 재질은 `FP_ShieldLeatherEdge`, `FP_ShieldOak`, `FP_ShieldIron`, `FP_ShieldEdge`, `FP_ShieldEnarmes`, `FP_ShieldStitch`다. 메시·UV·재질 이름을 보존한다. Godot의 `_prepare_sword_shield_materials`는 표시 재질도 조정하므로 geometry 일치와 shader 표시 일치를 별도로 보고한다.

## 2. 게임 계층과 단 하나의 올바른 변환식

```text
PlayerCamera
  ShieldPivot                      # 이 노드의 절대 camera-local T를 전달
    WeatheredRoundShieldVisual      # 원본 GLB 루트; Q=Ry(PI), scale=1
      SwordsmanRoundShield_Surface  # 원본 model-local 정점
      RearGrip / RearGripTop / RearGripBottom / RearArmStrap
    SwordShieldArm                 # 방패 모델의 자식이 아닌 피벗의 별도 자식

Q = diag(-1, 1, -1, 1)             # homogeneous Ry(PI)
vertex_camera(t) = T_ShieldPivot(t) * Q * vertex_model
marker_camera(t) = T_ShieldPivot(t) * Q * marker_model
```

근거: `scripts/player.gd:444–457`에서 원본을 instantiate한 다음 `shield_model.rotation.y = PI`를 적용한다. 소유자는 실제 뒤쪽 손잡이를 보고 boss는 상대 방향을 향한다. **Q를 T에 구운 채 전달하면 게임에서 Q가 다시 적용된다.** 전달하는 T는 `ShieldPivot` 기준이고 Q를 포함하지 않는다. sword의 `SOURCE_READY.inverse()` 정점 정규화는 이 방패에 적용하지 않는다.

`_build_shield`의 초기 생성 위치 `(-0.72,-0.76,-0.82)`는 재생 준비 전 초기값이다. 아래 CHOREOGRAPHY idle을 제작 기준으로 사용한다. 새로운 authored idle은 그와 다른 자세일 수 있지만, 원본 모델 Q와 좌표 정의는 유지한다.

## 3. 기존 idle의 정확한 basis

`scripts/sword_shield_choreography.gd:143` 및 `delivery_requirements.json/canonical_shield`의 기준은 position `(-0.34,-0.30,-0.60)`, 각도 XYZ `(-19.28,83.44,20)`도다. Godot 기본 Euler 순서 **YXZ**는 `Ry(y)*Rx(x)*Rz(z)`다. Blender XYZ Euler로 해석하지 않는다. [Godot 공식 구현의 set_euler](https://github.com/godotengine/godot/blob/master/core/math/basis.cpp#L613-L636)에서 순서를 확인했다.

다음은 열벡터에 곱하는 4×4 행렬의 **행**이다. `mathutils.Matrix(rows)`로 만들 수 있다.

```text
S_shield =
[[-0.004836632055, -0.347314528956,  0.937736223555, -0.34],
 [ 0.322838376369,  0.886991149207,  0.330184923902, -0.30],
 [-0.946441751897,  0.304334222862,  0.107836408793, -0.60],
 [ 0,               0,               0,               1   ]]

rotation_xyzw = [-0.009162558942, 0.667830699442, 0.237529941082, 0.705335190875]
position      = [-0.34,-0.30,-0.60]
```

JSON `basis_columns`로 쓸 경우 위 3×3의 열을 뽑는다. Blender Quaternion의 생성·출력 순서 `[w,x,y,z]`와 전달 순서 `[x,y,z,w]`를 구분한다. 반대 부호의 quaternion도 같은 회전이지만 연속 프레임에서는 hemisphere를 유지한다. 위 행렬은 **피벗 S_shield**다. 모델의 최종 idle 행렬은 `S_shield*Q`이므로 첫째·셋째 basis 열만 부호가 반대다.

REFERENCE의 authored shield idle이 나중에 존재하면 `CHOREOGRAPHY.shield()` 결과가 이를 사용한다. 그때 함수 결과로 제작 기준을 다시 추정하지 말고 이 문서의 고정 S_shield와 새 idle을 구분한다.

## 4. 실제 크기와 rim 기준

원본 model-local XY가 방패 판의 평면이고 +Z 쪽에 boss, -Z 쪽에 실제 후면 손잡이가 있다. 원점 `(0,0,0)`은 모델·피벗 중심이며 RearGrip이나 전체 3D AABB 중심이 아니다.

| 측정 | 실제 POSITION 값 |
| --- | --- |
| 전체 X 범위 | `[-0.427135527,+0.427135527]` m |
| 전체 Y 범위 | `[-0.426869988,+0.427130014]` m |
| 전체 Z 범위(손잡이·boss 포함) | `[-0.139735460,+0.083999999]` m |
| rim XY 지름 | X `0.854271054`, Y `0.854000002` m |
| 원점 기준 최대 XY 방사거리 | `0.427555750` m |
| 바깥 rim 정점(r>0.42m)의 Z 범위 | `[-0.011,+0.025]` m |

rim은 완벽한 수학 원이 아니므로 반경 0.427m로 새 원판을 다시 만들지 않는다. 기존 radius 0.32m 프록시의 지름 0.64m보다 실제 X 지름은 약 **33.48% 크다**. 깊이·크롭·회전이 다르게 보이므로 실제 모델로 다시 맞춘다.

아래는 실제 극단 rim 단면의 중심으로 계산한 확인점이다. 단일 vertex가 아니며 JSON에 근거 POSITION accessor 12/18과 정점 index를 기록했다. 모델을 기울이면 이 점들이 화면의 좌·우·상·하 극점이라는 보장은 없다. 최종 2D rim은 전체 실제 테두리 정점을 카메라에 투영해 평가한다.

| model-local rim 확인점 | `[x,y,z]` |
| --- | --- |
| 최소 X 단면 중심 | `[-0.427135527,0.013982969,0.0075]` |
| 최대 X 단면 중심 | `[+0.427135527,0.013982969,0.0075]` |
| 최소 Y 단면 중심 | `[0,-0.426869988,0.0075]` |
| 최대 Y 단면 중심 | `[0,+0.427130014,0.0075]` |

## 5. 중심과 실제 후면 파지 marker

| marker | 원본 model-local | Q 적용 후 ShieldPivot-local |
| --- | --- | --- |
| model origin | `[0,0,0]` | `[0,0,0]` |
| RearGrip | `[-0.180000007,0.015,-0.128735811]` | `[+0.180000007,0.015,+0.128735811]` |
| RearGripTop | `[-0.184098199,0.073606886,-0.101669274]` | `[+0.184098199,0.073606886,+0.101669274]` |
| RearGripBottom | `[-0.175901800,-0.043606889,-0.100730509]` | `[+0.175901800,-0.043606889,+0.100730509]` |
| RearArmStrap | `[+0.129999995,-0.005,-0.111456811]` | `[-0.129999995,-0.005,+0.111456811]` |

S_shield에서 model origin의 camera 위치는 `[-0.34,-0.30,-0.60]`, RearGrip은 약 `[-0.225360079,-0.186077599,-0.751912101]`다. 이 두 점을 겹치게 놓으면 피벗 정의가 바뀐다. 원본 root origin을 손잡이로 이동한 경우 반드시 그 보정을 child model 쪽으로 보존하고 T는 원래 피벗 기준으로 반환한다.

현재 왼손은 `player.gd:2570–2589`에서 이 실제 RearGrip에 놓이며, Top–Bottom 축과 `RearArmStrap_camera - T.basis.z*0.04`를 사용해 손목/전완 방향을 정한다. 단순 원판 프록시에는 이 정보가 없다. 방패 모델 변환에 별도 임의 pivot 보정을 넣으면 파지가 끊어진다.

## 6. Windows import와 절대 샘플 추출

1. 실제 원본 GLB를 별도 Blender 파일에 import하고 SHA와 네 named marker를 확인한다. 최초 import의 계층·오브젝트 transform을 임의로 apply/reset하지 않는다. Blender의 Z-up 변환이 오브젝트 또는 정점 어느 쪽에 적용되었는지 marker와 정점으로 확인한다.
2. 제작용 `ShieldPivot` controller를 카메라 아래 개념상 놓고, 그 아래에 `Q=Ry(PI)`와 **원본 geometry 좌표 보정**을 둔다. 실제 모델의 샘플 포즈가 `Bcam*T*Q*v_model`에 일치해야 한다. 여기서 Bcam은 Blender 카메라 월드 행렬이다.
3. Blender 카메라 local은 +X 오른쪽,+Y 위,-Z 전방으로 같은 관례다. canonical controller를 구성한 뒤에는 `T = inverse(Bcam) * ShieldPivot.matrix_world`를 직접 샘플한다. camera-local T에 월드 축 변환을 다시 곱하지 않는다.
4. untouched GLB import의 Blender 월드 좌표가 `C*v_import_world = v_model`을 만족하는 경우, `C(x,y,z)=(x,z,-y)`를 geometry 아래 정적 보정으로 사용할 수 있다. 예를 들어 원래 root 행렬이 M_import이면 최종 모델 root 행렬은 `Bcam*T*Q*C*M_import`다. 이 공식의 전제는 RearGrip와 rim 실제값으로 검증한다. 이미 model-local 정점을 기준 좌표로 바꾼 경우 C는 생략한다. C와 Q는 controller의 반환 T에 섞지 않는다.
5. 기준 delta 방식이 필요하면 실제 모델이 S_shield*Q 자세로 맞춰진 controller의 `A_rest`를 기록하고 `D=A(t)*inverse(A_rest)`, `T=D*S_shield`를 쓴다. 확인되지 않은 disk proxy의 A_rest를 여기에 대입하지 않는다.

## 7. 검토 납품 조건

- 실제 evaluated `ShieldPivot`의 `position:[x,y,z]`, `rotation_xyzw:[x,y,z,w]`, scale=1을 기존 sword와 같은 time_seconds에 기록한다. 표시 메타데이터는 `absolute_ShieldPivot_local_to_camera`, 원본 SHA, 실제 모델 여부를 포함한다.
- 실제 GLB 원본, Q, T와 marker를 사용해 대표 프레임의 `T*Q*RearGrip` 및 rim 투영이 Blender 평가 결과와 일치하는지 확인한다. geometry 오차와 shader/텍스처 검토 상태를 구분한다.
- 기존 proxy 샘플은 보존하되 최종 production shield 트랙으로 로드하지 않는다. 실제 모델을 검사한 절대 피벗 트랙만 최종 검토 JSON/manifest에 넣는다.
- 새로운 idle 또는 공격 방패 자세는 사용자 참조의 실제 화면 점과 비교해 결정한다. 이 문서의 S_shield는 기존 게임 좌표·앞뒤 방향의 확인 기준이며 새 동작 연출을 강제하는 키프레임이 아니다.

원본 해시 보존과 JSON 재읽기만 확인했다. 이 계약 작성에서는 Blender·렌더·게임 테스트를 실행하지 않았다.
