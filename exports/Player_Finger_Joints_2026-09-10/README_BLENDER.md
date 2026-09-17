# Blender에서 손가락 관절 검토하기

같이 제공된 `bilateral_hands_articulated.blend`를 열고 **Bilateral_Articulated_Review** 장면을 선택합니다. 제작 검토본은 [iteration_02의 편집 파일](bilateral_hands_articulated.blend)입니다.

| 구분 | 왼손 | 오른손 |
|---|---|---|
| 검토용 배치 부모 | `LEFT_PreviewTranslationOnly` | `RIGHT_PreviewTranslationOnly` |
| 포즈를 조작할 Armature | `HandRig.001` | `HandRig.003` |
| 보정 Shape Key가 있는 손 표면 | `ContinuousAnatomicalHand.001` | `ContinuousAnatomicalHand.003` |
| 손톱 | `Nail_thumb`, `Nail_index`, `Nail_middle`, `Nail_ring`, `Nail_little` | 같은 이름에 `.001` 접미사 |

좌우 모두 `wrist` 1개와 손가락 본 15개를 사용합니다. `thumb`는 엄지, `index`는 검지, `middle`은 중지, `ring`은 약지, `little`은 새끼손가락입니다. 각 이름 뒤의 `0`, `1`, `2`가 뿌리·중간·끝 관절을 나타냅니다. 엄지의 `thumb0`는 손바닥 안쪽에서 움직임을 시작하는 기저 관절입니다.

## 한 마디만 굽히기

1. 해당 손의 Armature를 선택하고 **Pose Mode**로 들어갑니다. 다른 본을 선택 해제한 뒤, 예를 들어 검지 중간 마디인 `index1`만 선택합니다.
2. 본의 **로컬 X축을 음수 방향**으로 회전합니다. 중립 상태에서 `R → X → X → -55 → Enter`를 입력하면 해당 로컬 축을 기준으로 55° 굽힙니다.
3. **Object Mode**로 돌아가 같은 손의 `ContinuousAnatomicalHand...`를 선택합니다. **Object Data Properties → Shape Keys**에서 `Joint_index_1`의 Value를 `0.5`로 설정합니다. 이 관절의 최대 굽힘이 110°이므로 `55 ÷ 110 = 0.5`입니다.

각 보정 키의 이름은 **`Joint_<손가락>_<관절번호>`**이며 한 손에 15개입니다. 키 값은 `굽힘 각도의 절댓값 ÷ 해당 관절 최대 각도`로 계산하고 `0–1` 범위에서 사용합니다. 본 회전과 Shape Key는 서로 다른 조작입니다. 이 편집 파일에는 두 값을 자동 연결하는 드라이버나 재생용 애니메이션이 설정되어 있지 않습니다.

| 손가락 | 0번 관절 | 1번 관절 | 2번 관절 |
|---|---:|---:|---:|
| 엄지 `thumb` | −60° | −70° | −80° |
| 검지 `index` | −90° | −110° | −80° |
| 중지 `middle` | −90° | −110° | −80° |
| 약지 `ring` | −90° | −110° | −80° |
| 새끼손가락 `little` | −90° | −110° | −80° |

부모 마디를 굽히면 같은 손가락의 아래쪽 마디와 손톱이 함께 따라갑니다. 한 마디의 회전만 검토하려면 다른 본의 회전과 다른 보정 키는 중립으로 둡니다.

## 중립으로 되돌리기

Pose Mode에서 조작한 본을 선택하고 **Alt+R**로 포즈 회전을 지웁니다. 손 표면의 `Joint_...` Shape Key Value도 각각 `0`으로 되돌립니다. 파일에 저장된 기본 상태는 모든 관절 포즈 회전이 중립이고, 보정 키 15개가 모두 `0`인 상태입니다. `Basis`는 원래 열린 손의 형태입니다.

보정 키는 관절을 굽힐 때 바깥쪽 볼륨과 안쪽 접힘을 조금 보강합니다. 손톱에는 보정 키가 없으며 각 손가락의 `2`번 본을 그대로 따라갑니다. 큰 굽힘에서 손톱 밑 피부가 벌어지지 않도록 말단 피부 가중치에 부드러운 전이를 적용했습니다.

## 배치와 파일 보존

검토 장면의 좌우 부모는 양손을 나란히 보여 주기 위한 배치입니다. 게임에 가져갈 때는 함께 제공된 `left_hand_articulated.glb`, `right_hand_articulated.glb`를 사용합니다. 개별 GLB에는 이 검토용 좌우 이동이 없으며, Blender 기준 원래 손목 위치 **`(0, −0.05625, 0)` m**와 16개 본의 바인드 상태를 유지합니다.

기존 디테일 모델과 그레이박스 원본은 별도로 보존되어 있습니다. 추가 편집은 **Save As**로 새 파일에 저장하는 것을 권장합니다. `joints_open_...`, `joints_flex_...`, `joints_independent_index_1.png`는 실제 열린 손·최대 굽힘·검지 중간 마디 독립 굽힘을 렌더한 검토 이미지이며, 해당 포즈가 편집 파일에 활성 상태로 저장된 것은 아닙니다.
