# 육포 파지 보정 / Jerky grip calibration

## 기준 / Source

- 음식: `beef_jerky_variants.glb`의 `Jerky_01_long_torn_strip`, 원래 메시 좌표와 크기를 유지합니다. 긴 방향은 +X이며 입으로 가져가는 끝입니다.
- 손: `assets/3d/player/fp_arms/right.scn`의 `FP_R_Hand`, 현재 `supplied_fp_arm.gd`의 손 크기 1.30을 적용한 실제 스킨입니다.
- 검지 패드 정점: **156**. 엄지 패드 정점: **17**. 이 번호는 손 메시의 첫 표면에 대한 번호입니다.

Food uses the original long-strip geometry, with its positive X end toward the mouth. Contact is fitted to the supplied right hand after its existing 1.30 hand scale. Vertex 156 is the index pad and vertex 17 is the thumb pad on the first hand surface.

## 방법과 측정 / Method and measurements

손가락 관절의 기존 회전축과 허용 굽힘 범위에서 검지·엄지 패드가 서로 마주보도록 맞췄습니다. 손목 위치를 기준으로 한 음식 변환은 `scripts/jerky_eat_visuals.gd`의 `food_in_hand`이며, 손목 월드 변환은 `food.transform * food_in_hand.affine_inverse()`입니다. 전체 음식을 줄이거나 손에 붙이는 기준점을 이동해 맞추지 않습니다.

The fit uses the existing finger hinge axes and flexion limits. `food_in_hand` is the food transform in wrist space. The wrist follows the food with the inverse of that transform. Bites preserve the held part of the food and the grip transform.

| 측정 / Measurement | 값 / Value |
| --- | --- |
| 음식 접촉 X / Food contact X | −0.055 m |
| 음식 접촉 Z / Food contact Z | −0.003 m |
| 검지–엄지 피부 간격 / Skin pad separation | 4.510 mm |
| 검지–육포 아래 표면 / Index to lower food surface | 0.349 mm |
| 엄지–육포 위 표면 / Thumb to upper food surface | 0.787 mm |
| 보정 자세의 육포 내부 손 정점 / Hand vertices inside food in fitted pose | 0 / 2,031 |

패드 손목 좌표 / Pad coordinates in wrist space:

```text
index 156: (-0.02014297, -0.06452801, -0.10618392)
thumb 17:  (-0.01873883, -0.06377617, -0.10196467)
```

수치 보정 결과를 Godot의 실제 뼈 변환과 스킨 바인드 행렬로 다시 계산했고, 패드 위치는 1 μm 이내로 일치했습니다. 위 표면 거리는 단순 상자가 아닌 원본 육포의 삼각형 메시를 기준으로 측정했습니다.

Godot's actual bone transforms and skin bind matrices reproduced the fitted pad positions within 1 μm. Surface distances use the irregular food triangles, not a bounding box.

## 회귀 검증 / Regression check

```sh
godot-game/tests/run_headless_tests.sh jerky_grip
```

`tests/jerky_grip_test.gd`는 꺼내기, 두 번의 입 접촉, 씹기와 내리기 구간의 여섯 시점에서 실제 피부와 음식 표면을 검사합니다. 각 패드는 표면에서 2 mm 미만으로 유지되고, 1.5 mm를 넘는 피부 정점 관통은 실패합니다. 원래 손 메시와 연결된 팔 메시가 보이는 상태도 검사합니다. 이 검사는 팔 전체가 서로 교차하는지 또는 화면의 자연스러운 구도를 판정하지 않으므로 별도의 실제 렌더 검토를 함께 사용합니다.

The test checks six times across draw, both bites, chewing and lowering. Pads must remain within 2 mm of the surface; hand-vertex penetration over 1.5 mm fails. It also requires the complete hand and connected forearm meshes. These measurements do not establish full arm collision or visual composition, which need the separate rendered review.
