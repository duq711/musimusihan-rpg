# Windows 재제작용 Godot 오른팔 포즈 계약

작성: 2026-09-10. 현재 Mac Godot 소스와 보존 GLB를 읽어 만든 좌표·연결 계약이다. 새 동작 키프레임, Blender 제작 결과, 게임 반영 완료를 의미하지 않는다. 첫 제작 대상은 내리찍기 하나이며, 영상의 구도·타이밍 판단은 별도의 실제 참조 프레임과 비교한다.

**손·검 파지 고정은 팔 전체 rigid 이동을 뜻하지 않는다.** 장갑과 검 사이의 상대 변환은 보존한다. 어깨·팔꿈치·전완·커프는 각각 움직일 수 있어야 한다. 현재 Godot도 이 둘을 구분한다. 새 별도 파일에 관절 리그와 스킨을 추가하는 것은 가능하며, 정적 원본에 원래 리그가 있었다고 표시하지 않는다.

## 1. 보존 대상과 메시 역할

- Godot 원본: `godot-game/assets/3d/player/sword_hold_long_grip/SwordHold_Static.glb`
- GLB SHA256: `2b94cc385f837fe253552cd654cb1f665246f61cdee5227814d63049da9f22fb`
- 보존 Blender 원본: `asset-staging/sword_hold_long_grip_integration/source/model/SwordHold_Static.blend`
- 원본 GLB를 직접 읽은 결과: 메시 11개, skin 0개, animation 0개. 원본 파일과 텍스처는 덮어쓰지 않는다. 리그·변형은 복제한 작업 파일에 만든다.

| 원본 메시 이름 | 현재 Godot 역할 / Windows 재현 조건 |
| --- | --- |
| `RightHand_Glove` | 검과 동일한 포즈. 손가락을 다시 펴거나 파지를 바꾸지 않는다. |
| `RightArm_Forearm_Surface` | 손목→팔꿈치의 별도 구간 변환. |
| `RightArm_UpperArm_Surface` | 팔꿈치→어깨의 별도 구간 변환. |
| `RightArm_WristCuff_Surface` | 손목을 피벗으로 전완 회전을 따른다. 자체 스케일은 1. |
| `Sword_FullerPolishedChannel`, `Sword_GripBinding`, `Sword_GripBinding_Extension`, `Sword_GripLeather`, `Sword_GripLeather_Extension`, `Sword_PittedBlade`, `Sword_SwordsmanLongsword_Surface` | 7개 검 메시 모두 장갑과 같은 강체 포즈. |

현재 계층은 `Camera / WeaponPivot(T) / LongGripSwordArm(identity) / {glove, forearm, upper_arm, cuff}`와 같은 피벗의 검 메시다. `WeaponPivot`의 변환을 먼저 결정한 뒤 팔을 맞춘다. 장갑 로컬 변환은 identity이고 소매만 추가 변환을 가진다. 원본의 오브젝트 원점을 손목이나 손잡이로 추정하지 않는다.

## 2. 좌표와 정규화: 반드시 한 번만 적용

이 문서의 모든 수치는 미터, 카메라 로컬 `+X 오른쪽, +Y 위, -Z 전방`이다. 행렬은 열벡터에 왼쪽에서 곱한다. `S=SOURCE_READY`는 원본을 정규화하는 영구 기준이며 새 idle 구도를 맞추려고 수정하지 않는다.

Godot `Basis` 생성자의 세 벡터는 **열**이다. 아래는 Blender `mathutils.Matrix`에 사용할 수 있도록 전치 표기를 풀어 쓴 **행** 목록이다.

```text
S = [ [ 0.6734562112, 0.1384824613, -0.7261403196,  0.3249563841 ],
      [-0.1673592395, 0.9853534854,  0.0327005009, -0.0035816696 ],
      [ 0.7200327879, 0.0995039315,  0.6867691389, -0.5892537756 ],
      [ 0,            0,             0,             1            ] ]
```

`M_i`를 원본 GLB 메시 i의 루트까지 누적한 카메라 공간 변환, `v_i`를 그 메시의 원래 정점으로 두면:

```text
v_canonical = inverse(S) * M_i * v_i
T(t)        = 카메라 기준 검 피벗의 절대 변환 (회전+위치, scale=1)
glove/sword vertex_camera(t) = T(t) * v_canonical
```

따라서 `T=S`이면 원래 GLB 자세와 정확히 겹친다. 기존 카메라 배치의 정점에 `T`만 곱하면 S를 중복 적용한 것이다. 소매의 정점도 같은 canonical 공간에 먼저 둔다. 메시 로컬 좌표, GLB 누적 노드 좌표, Blender 월드 좌표를 혼동하지 않는다.

Blender 카메라 로컬 축도 `+X 오른쪽, +Y 위, -Z 시선`이다. 고정 카메라의 월드 행렬을 `Bcam`, 검·장갑 컨트롤의 카메라 상대 행렬을 `A(t)=inverse(Bcam)*M_control(t)`로 두면 기존 컨트롤 축을 보존하는 경로는 `D(t)=A(t)*inverse(A_rest)`, `T(t)=D(t)*S`다. canonical 정점을 이미 만든 경로는 직접 `M_control(t)=Bcam*T(t)`를 사용한다. 두 경로를 중복 적용하지 않는다.

Blender 월드의 Z-up 변환 `C(x,y,z)=(x,z,-y)`는 별도의 좌표 변환 경로다. 위 카메라 로컬 결과에 C를 다시 곱하지 않는다. 원본 Blender 카메라와 새 카메라의 상대 배치가 다르면 `T=S` 겹치기부터 확인한다. export quaternion은 최종 행렬에서 추출하고 JSON은 `[x,y,z,w]` 순서로 쓴다. Blender Quaternion 생성/출력의 `[w,x,y,z]` 순서와 구분한다.

## 3. 실제 기준점과 카메라 공간 확인값

아래 camera 값은 새 동작을 추정한 것이 아니라 현재 코드의 `S * canonical_point`를 산술 계산한 값이다.

| 기준점 | canonical `[x,y,z]` | `T=S`의 camera `[x,y,z]` |
| --- | --- | --- |
| 손잡이 중심 G | `[0,-0.108,0.002]` | `[0.308547997640,-0.109934445021,-0.598626661924]` |
| 칼끝 | `[0,1.035,0]` | `[0.468285731546,1.016259187789,-0.486267206498]` |
| 손목 W0 | `[0.0679751875,-0.1080001335,0.0524637313]` | `[0.317682541408,-0.119660662960,-0.515025378154]` |
| 팔꿈치 E0 | `[0.2366280243,-0.1080001099,0.2503430693]` | `[0.287574679418,-0.141415496742,-0.257692380973]` |
| 어깨 H0 | `[0.4571740416,-0.1080000789,0.5091083575]` | `[0.248202859842,-0.169864125386,0.078819999963]` |

파지 중심 G와 손목 W0는 다른 점이다. 검과 장갑은 G를 공유하지만 전완 회전은 W0에서 시작해야 한다. 원본은 거의 일직선으로 뻗은 팔이다. 현재 코드가 실제 계산에 사용하는 길이는 `L_forearm=|E0-W0|=0.260000022631`, `L_upper=|H0-E0|=0.340000029594`다. 선언된 0.26/0.34와의 작은 차이는 입력 정밀도 차이다.

## 4. 현재 Godot를 동일하게 재현하는 관절 계산

현재 static-grip 경로에서 shoulder는 `H=S*H0`로 **카메라에 고정**이다. 일반 팔 코드의 `(0.29,-0.34,0.10)`이나 공격용 다른 shoulder 함수는 이 경로에 적용하지 않는다. 손목은 `W=T*W0`, 손잡이는 `T*G`다. 모든 다음 계산은 카메라 공간에서 해도 현재 월드 계산과 같다.

```text
U = |H0-E0| ; F = |E0-W0|
d = W-H ; r = |d| ; a = d / max(r, 0.00001)
E = H + d * U/(U+F)                         # 도달 불가능할 때의 현재 fallback
if abs(U-F) < r < U+F:
    x = (U*U - F*F + r*r) / (2*r)
    p = (0.75,-0.72,0.28)                  # 카메라 공간 pole 방향; 위치가 아님
    b = normalize(p - a*dot(p,a))
    E = H + a*x + b*sqrt(max(0,U*U-x*x))
```

`x`는 코사인 법칙으로 구한 어깨→팔꿈치의 축 방향 거리다. 이 분기에서 `|E-H|=U`, `|W-E|=F`가 동시에 성립한다. pole은 카메라 기준 바깥·아래쪽으로 팔꿈치가 굽도록 한다. 실제 Godot `fit_arm()`에는 다음 원본 복귀 예외가 있다: `|inverse(T)*H - H0| < 1e-5`이면 local shoulder=H0, local elbow=E0를 강제로 사용해 원본의 곧은 소매를 정확히 되돌린다.

**현재 한계:** r이 약 0.08–0.60m 밖이면 fallback은 팔을 일직선으로 놓고 길이를 `r/(U+F)`배로 늘리거나 줄인다. 최대 늘어남 제한이 없다. pole과 a가 평행할 때의 추가 bend 안정화도 이 경로에는 없다. 이 동작은 현 게임 재현용 사실이며 새 모션의 품질 목표가 아니다.

## 5. 전완·상완·커프의 정확한 변환 순서

`h=inverse(T)*H`, `e=inverse(T)*E`로 현재 관절을 canonical 피벗 로컬로 가져온다. 각 구간의 원래 양끝을 `(a0,b0)`, 현재 양끝을 `(a1,b1)`이라고 하면:

```text
u = normalize(b0-a0)
v = normalize(b1-a1)
k = |b1-a1| / |b0-a0|
K = I + (k-1) * outer(u,u)                 # 구간 축만 늘림; 반경은 유지
R = shortest rotation from u to v
B = R*K
F_segment = [ B, a1-B*a0 ]                 # 두 끝점을 정확히 연결
```

현재 R은 `axis=normalize(cross(u,v))`, `angle=atan2(|cross(u,v)|,dot(u,v))`로 만든다. cross 길이 ≤1e-9이고 dot<0이면 u에 수직인 축으로 π 회전한다. 구간 길이 <1e-5면 identity를 반환한다. 임의의 look-at 축은 작은 포즈 차이에서도 roll을 뒤집을 수 있으므로 같은 shortest-rotation을 사용한다.

```text
F_forearm = fit(W0,E0, W0,e)
F_upper   = fit(E0,H0, e,h)
Q         = orthonormalize(F_forearm.basis)
F_cuff    = [ Q, W0-Q*W0 ]

forearm vertex_camera = T * F_forearm * v_canonical
upper   vertex_camera = T * F_upper   * v_canonical
cuff    vertex_camera = T * F_cuff    * v_canonical
glove   vertex_camera = T            * v_canonical
```

Blender에서 canonical 정점으로 복제한 소매 오브젝트의 최종 월드 행렬은 `Bcam*T*F_part`다. 부모가 이미 `Bcam*T`라면 자식 로컬에 F_part만 둔다. parent inverse와 오브젝트 원점을 중복 보상하지 않는다. 최종 평가 행렬/정점으로 검증한다.

`orthonormalize`까지 현재 Godot와 똑같이 맞출 때는 basis 열의 Gram–Schmidt를 쓴다: `qx=normalize(x)`, `qy=normalize(y-qx*dot(qx,y))`, `qz=normalize(z-qx*dot(qx,z)-qy*dot(qy,z))`. Blender의 행렬 열별 normalize만으로 대체하지 않는다. 도달 가능한 무스케일 구간에서는 Q=R이다. 커프는 전완의 축 스케일을 복사하지 않는다.

## 6. 열린 소매 끝과 길이 제약

기존 접합 검증의 수치 조건은 다음과 같다. 이는 좌표 재현 확인이며 화면 품질 합격을 대신하지 않는다.

- 손목: `T*F_forearm*W0 = T*W0`.
- 팔꿈치: `T*F_forearm*E0 = T*F_upper*E0 = E`.
- 어깨: `T*F_upper*H0 = H`.
- 커프: `T*F_cuff*W0 = T*W0`, scale=1, 회전은 전완 orthonormal basis와 일치.
- 위 endpoint 오차는 각각 ≤0.00003m로 현재 시험에서 확인한다. 파지는 ≤0.0001m를 넘기지 않는 별도 보고 대상으로 둔다.

커프를 검과 함께 고정하면 전완이 꺾일 때 열린 뒤쪽 테두리가 카메라에 드러난다. 커프를 W0 중심으로 전완과 같이 돌려야 한다. 중심선의 endpoint 일치만으로 원통 테두리 전체가 봉합되지는 않는다. 깊게 굽힌 팔꿈치, 손목 비틀림, 어깨 뒤쪽의 열린 끝은 실제 1인칭 및 외부 측면 프레임에서 확인한다. 기존 포즈의 어깨 z가 +0.07882m로 카메라 뒤에 있다는 사실만으로 새 공격도 가려진다고 가정하지 않는다.

새 내리찍기는 가능한 한 뼈 길이 U/F를 유지한다. 손목 궤적이 고정 어깨의 도달 범위를 벗어나면 작은 어깨 움직임, 팔꿈치 경로, 검 깊이를 함께 조정하고 실제 참조 실루엣을 재검토한다. 손·검을 떼거나 소매를 무한히 늘려 봉합하지 않는다. 제작 검증에서는 길이 비율을 매 프레임 기록하고 **1% 초과 변화는 실패로 보고하는 초기 제작 기준**을 사용한다. 이는 아직 Godot 코드에 존재하는 제한이 아니다.

영상에서 보이는 2D 파지 위치는 3D 깊이를 유일하게 정하지 않는다. 이전 검토의 idle 깊이 약 0.60m를 새 리그에 강제하지 않는다. 깊이를 고정한 채 손을 화면 아래로만 내리면 원본 어깨에서 손목까지 거리가 0.60m 한계를 넘을 수 있다. 실제 원본 메시·카메라 투영·`|W-H|`를 함께 평가해 깊이와 자세를 찾는다. shoulder는 몸에 연결된 작은 범위 안에서 움직이도록 저작하고, 매 프레임 `|H(t)-S*H0|` 및 최대 이동량을 보고한다. 어깨를 손과 함께 화면 앞으로 끌고 나와 도달 거리만 맞추지 않는다.

원본 소매가 관절 굽힘을 감당하지 못하면 별도 복제본에 스킨 가중치, 관절 연결 메시, 보이지 않는 내부 마감을 추가할 수 있다. 그 경우 변경된 메시와 원본 메시를 구분해 납품하며 원본 해시 보존과 최종 변형 품질을 각각 검증한다. 커프의 두께·접합부를 처리해야 하며, 단면을 검은 면으로 가리는 것만으로 해부학적 연결이 해결됐다고 보지 않는다.

## 7. 재제작 리그와 전달 계약

첫 내리찍기는 최소 `SwordGrip`(검+장갑), `Shoulder_R`, `ElbowPole_R` 또는 `Elbow_R`, `Forearm_R`, `UpperArm_R`, `WristCuff_R`를 독립적으로 평가 가능하게 만든다. 관절/스킨 리그를 사용할 수 있고, 검은 손의 파지 소켓에 고정해도 된다. 검과 손 중 어느 쪽이 리그를 구동하든 **평가 후 상대 파지 변환은 동일**해야 한다. 어깨·팔꿈치까지 SwordGrip의 한 rigid 자식으로 움직이는 구조는 금지한다.

현재 Godot의 H 고정·E 자동 계산은 비교용 baseline이다. 새 액션에 저작한 H(t), E(t), forearm twist를 반영하려면 이 값들을 실제로 전달해야 한다. sword 피벗 하나만으로는 팔꿈치의 선택·비틀림·어깨 선행을 복원할 수 없다.

우선 검토용 게임 어댑터는 현재 정규화 메시와 `fit_arm()`을 유지하면서, 새로 저작한 camera-local shoulder/elbow를 월드로 옮겨 넘기는 방식으로 만들 수 있다. 이 경우 player의 현재 E 자동 추정은 사용하지 않으며 Windows도 5절의 동일한 `fit_segment`로 표면을 평가해야 한다. 이는 앞으로 구현할 통합 방향이며 지금 게임에 해당 입력이 연결되어 있다는 뜻은 아니다. 별도 forearm twist나 새 스킨 변형을 저작했다면 이 최소 경로가 그것까지 보존한다고 가정하지 않는다.

최소 납품은 편집 가능한 리그 `.blend`, 재가져오기 검증된 animation `.glb`, 실제 Blender 평가 결과의 아래 sidecar다. 기존 `motion_manifest.json`에는 `sword`/`shield` 트랙만 허용되므로 임의의 arm 트랙을 거기에 삽입하지 않는다. 새 sidecar는 **아직 런타임 미지원인 별도 통합 입력**이며 root가 실제 결과를 검토한 뒤 게임 어댑터를 결정한다.

```text
arm_pose_samples.json (구조 설명; 아래에는 authored sample 값을 넣지 않음)
  schema_version: 1
  status: authored_windows_output
  clip_id: overhead
  coordinate_space: godot_camera_local_x_right_y_up_minus_z_forward
  geometry_space: canonical_source_ready_inverse
  seconds_basis: original_authored_clip_seconds
  frames[]:
    time_seconds
    sword: { position:[x,y,z], rotation_xyzw:[x,y,z,w] } # 절대 T
    shield: { position:[x,y,z], rotation_xyzw:[x,y,z,w] } # 기존 트랙과 같은 시각의 절대 변환
    right_arm:
      shoulder: [x,y,z]                              # 카메라 위치
      elbow: [x,y,z]                                 # 카메라 위치
      wrist: [x,y,z]                                 # 카메라 위치; T*W0와 비교
      parts_camera:                                  # canonical 정점을 입력으로 받는 절대 행렬
        forearm:  { basis_columns:[[x,y,z],[x,y,z],[x,y,z]], position:[x,y,z] }
        upper_arm:{ basis_columns:[[x,y,z],[x,y,z],[x,y,z]], position:[x,y,z] }
        cuff:     { basis_columns:[[x,y,z],[x,y,z],[x,y,z]], position:[x,y,z] }
```

`parts_camera`는 `T*F_part`이며 raw Blender 오브젝트 local matrix가 아니다. basis에는 실제 축 스케일이 있으면 보존한다. 새 스킨 리그의 표면 변형은 이 세 행렬만으로 표현할 수 없으므로, 그 경우 GLB의 skin/bind/action이 실제 재생 계약이고 sidecar는 joint/파지 검증 자료다. bind transform, parent 관계, bone 이름 대응도 함께 납품한다. skeleton을 버리고 위 part 행렬만 적용한 프리뷰를 완성본으로 제시하지 않는다.

120Hz 권장, 최소 60Hz로 실제 dependency graph 평가를 베이크한다. 원래 클립 초 단위를 보존하고 타격 체크포인트를 명시한다. 게임 시간으로 미리 압축하지 않는다. 현재 게임의 재매핑과 영상 원래 리듬은 별개다. 이 문서는 Windows에서 새 동작을 제작하는 근거이며 Mac에서 authored sample을 합성하지 않는다.

검토 영상에는 내리찍기 한 번의 원래 속도 1인칭, 같은 프레임의 측면 관절 확인, 어깨/팔꿈치/손목 표시를 포함한다. 원본 손·검 구도 겹치기, 3개 관절 접합 오차, 프레임별 팔 길이/파지 오차, 커프 열린 끝 노출 여부를 함께 보고한다. 기존 Godot 장비 카메라는 FOV 76, near 0.025m를 사용하므로 재현 검토 시 원본 참조 카메라 설정과 게임 카메라 설정을 구분해 적는다.

## 8. 근거 소스

이 폴더의 `GODOT_ARM_SOURCE_EXCERPTS.txt`에 현재 소스의 최소 구간을 줄 번호와 파일 SHA256과 함께 보존했다. `GODOT_ARM_CONSTANTS.json`은 위 정적 기준점의 계산 결과로서 동작 샘플이 아니다.

- `scripts/sword_long_grip_visual.gd`: 상수 6–22, 파지·소매·커프·구간 변환 78–135, 메시 정규화 168–176 / 188–214.
- `scripts/player.gd`: 카메라와 계층 320–354 / 377–381, 피벗 적용 2251–2253, static grip 팔 계산 2485–2509.
- `tests/sword_long_grip_test.gd`: 실제 소매 접합 확인 `audit_sleeve_connections`.
- `scripts/first_person_renderer.gd`: 장비 카메라 설정 106–115.

코드는 바꾸지 않았다. 원본 GLB를 읽고 좌표값을 산술 확인했으며 Blender 실행·새 렌더·게임 테스트는 이 계약 작성 과정에서 수행하지 않았다.


## 2026-09-10 게임 재생 어댑터 개정

원본 복귀 예외는 기존 절차형 fallback에만 적용한다. `fit_arm(shoulder_world, elbow_world, preserve_authored_elbow=true)`로 평가된 Windows 관절을 적용할 때에는 어깨가 REST_SHOULDER에 있더라도 입력 elbow를 덮어쓰지 않는다. 검토 하네스와 v2 게임 경로는 이 명시적 모드를 사용하며, 1% 길이 계약에 맞는 20mm elbow 키가 실제 소매에도 남는 회귀를 통과했다. Windows의 독립 fit_segment 평가는 이 예외를 추가하지 않고 그대로 유지한다.
