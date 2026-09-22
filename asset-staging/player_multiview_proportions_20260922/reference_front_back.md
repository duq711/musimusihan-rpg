# 전신 정면·후면 비율 관찰 / Front and back reference proportions

사용자가 제공한 정면·후면 이미지를 원본 해상도에서 직접 확인했습니다. 좌표·비율은 3D 모델을 조정하기 위한 **관찰값과 근사값**이며 해부학적으로 정확한 스캔 치수가 아닙니다. 원본 참조 이미지는 수정하지 않았습니다.

The supplied front/back images were inspected at their original resolution. Measurements are observed image proportions and approximate surface landmarks, not calibrated anatomical scan dimensions. Source images were not edited.

## 좌표 / Coordinates

- 두 이미지 크기: 1086 × 1448 px.
- 정면: 머리카락 정수리 y=12, 부츠 밑창 y=1401, 보이는 높이 H=1389 px.
- 후면: y=10..1396, H=1386 px.
- normalized z=(sole_y-y)/H: 밑창 0, 머리카락 끝 1. normalized x=(x-533.5)/H.
- image_left/right는 이미지 좌우입니다. 정면과 후면의 해부학적 좌우를 혼동하지 않습니다.

## 주요 목표 범위 / Main target bands

| 기준 / Feature | 정면 z / Front | 후면 z / Back | 해석 / Meaning |
|---|---:|---:|---|
| 턱 / Chin | 0.8625 | — | 수염으로 ±0.004H / Beard obscures underside |
| 어깨 위·견봉 / Shoulder top | 0.8071 | 0.8081 | ±0.011H, 관절중심 아님 / Not joint centre |
| 추정 어깨 관절 / Inferred shoulder joint | 0.7840 | 0.7814 | ±0.014H, 피부 아래 숨김 / Hidden beneath deltoid |
| 팔꿈치 / Elbow | 0.660..0.661 | 0.6486 | 표면/시점 차이. 목표대역 약 0.65..0.67H |
| 손목 / Wrist | 0.5299 | 0.5209 | 목표대역 약 0.52..0.54H |
| 벨트 중심 / Belt | 0.5601 | 0.5750 | 의복 특징. 앞뒤 높이가 다름 / Clothing feature |
| 바지 가랑이 / Trouser crotch | 0.4442 | 0.4444 | 옷/주름 포함 ±0.006H |
| 추정 무릎 / Inferred knee | 0.3031 | 0.3009 | 헐렁한 바지 아래 숨김 ±0.018H |
| 부츠 상단 / Boot top | 0.2455 | 0.2453 | 의복 전환점 ±0.009H |

| 폭 / Projected width divided by H | 정면 / Front | 후면 / Back |
|---|---:|---:|
| 바깥 삼각근, y350 / Outer deltoids | 0.2937 | 0.3023 |
| 좁은 허리, y520 / Narrow waist | 0.1706 | 0.1645 |
| 바지 골반, y720 / Trouser hip | 0.2304 | 0.2266 |
| 손목 중심 간격 / Wrist separation | 0.4348 | 0.4315 |
| y420 상완 한쪽 / Upper arm, one side | 약 0.058 | 약 0.062 |
| y520 전완 한쪽 / Forearm, one side | 약 0.061 | 약 0.062 |

## 적용 판단 / Application

현재 모델의 큰 어깨·상완을 계속 키우는 방향은 이 전신 참조와 맞지 않습니다. 참조는 몸통·어깨 자체가 상대적으로 좁고, 허리가 들어가며, 손과 발의 간격은 비교적 넓은 편입니다. 몸통 폭과 팔다리 벌어짐은 별도로 맞춰야 합니다. 팔의 실제 단면은 투영된 가로폭보다 작을 수 있습니다.

The new full-body reference calls for a narrower shoulder/torso envelope with a defined waist, while keeping a moderately open hand and foot stance. Torso width and limb pose must be adjusted separately. Projected horizontal limb width is not the same as true perpendicular cross-sectional diameter.

머리카락까지 포함한 정면 머리 높이는 약 0.1375H입니다. 민머리 모델에 이 값을 그대로 적용하면 머리가 과대해질 수 있습니다. 숨겨진 두개골 정수리는 y32±14 px로만 추정했으며, 얼굴 위 끝의 정확한 위치는 판정할 수 없습니다. 바지와 부츠 때문에 무릎·골반·발목의 뼈 위치도 확정하지 않았습니다.

Visible head height including hair is approximately 0.1375H. Applying it directly to a bald model can over-enlarge the head. The obscured skull crown is only estimated at y32±14 px. Loose trousers and boots also prevent exact skeletal knee, hip and ankle measurements.

## 데이터 / Data

`reference_front_back.json` contains source SHA-256, every landmark with uncertainty, and deterministic silhouette samples at 39 image heights. Warm/dark foreground thresholding excludes the neutral background; silhouette edge uncertainty is approximately ±3 px. At shoulder heights arms and torso form one connected silhouette, so that width is explicitly distinguished from the separated central torso width below the armpits.

## 실제 모델 단위 보정 / Calibration to the actual game model

이 작업의 치수 보정은 **머리카락 끝(y12)이 아닌 추정 두개골 정수리(y36)** 를 기준으로 합니다. 모델의 발바닥 최저점 z=0.0076724137m, 정수리 z=1.71988809m, 높이 H=1.712215677m를 보존합니다. 따라서 참조의 해부학적 작업 높이는 1401−36=1365px이고, scale=1.712215677/1365m per pixel입니다.

The selected working calibration uses the estimated skull crown at y36, separately from visible hair at y12. It retains the model's current sole and bald skull-crown heights. This avoids enlarging the face merely to account for the reference hair volume.

`z_m = 0.0076724137 + (1401 - y_px) × 1.712215677 / 1365`

`x_m = (x_px - 533.5) × 1.712215677 / 1365`

| 정면 목표 / Front target | y px | 모델 z m / World height |
|---|---:|---:|
| 턱 / Chin | 203 | 1.51041 |
| 견봉·어깨위 / Acromion | 282 | 1.41131 |
| 추정 어깨관절 / Inferred shoulder joint | 312 | 1.37368 |
| 팔꿈치 / Elbow | 484 | 1.15793 |
| 손목 / Wrist | 665 | 0.93089 |
| 벨트중심 / Belt | 622 | 0.98483 |
| 가랑이 / Crotch | 784 | 0.78162 |
| 추정무릎 / Knee | 980 | 0.53576 |
| 부츠상단 / Boot top | 1060 | 0.43541 |

정면 상단 실루엣은 y260: x380..686 (폭0.3838m), y280: x354..710 (0.4466m), y310: x338..726 (0.4867m), y335: x330..733 (0.5055m), y350: x328..736 (0.5118m)입니다. 이 높이들은 팔과 몸통이 붙어 있으므로 **가슴 폭만을 나타내지 않습니다**. y420에서야 왼팔·몸통·오른팔이 각각 분리되고, 폭은 약0.1003/0.3437/0.1016m입니다.

The upper silhouette spans include both torso and deltoids/arms. They must not be applied directly as isolated rib-cage widths. At y420 the foreground separates into left arm, torso and right arm, approximately 0.1003 / 0.3437 / 0.1016m wide. All original pixel coordinates, hair-normalized measurements and calibration targets remain separately recorded in JSON.
