# 수정 전 3D 비율 측정 / Baseline 3D proportion measurements

`measurements.py` reads the current source `player_neck_arm_flow_20260922/Gravebound_Neck_Arm_Flow.blend` in background Blender without saving or altering it. Its triangle-plane intersections are recorded in `measurements.json`. Values are metres; Blender +Z is up and +Y is the front of the face. Slice widths include clothing, so they must not be presented as bare skeletal dimensions.

## 측정 / Measurements

- 전신 높이는 1.712 m, 정수리는 Z 1.720 m입니다. 머리+목 메시 전체 높이는 .279 m이며, 턱의 앞쪽 돌출이 시작되는 Z 약 1.510 m를 기준으로 얼굴/두개 높이는 약 .210 m입니다. 따라서 대략 8.15등신입니다. 턱 위치는 옷을 입은 정적 메시에서 추정한 값입니다.
- Head width including ears is .169 m; upper skull width is about .144 m. The neck is .140 m wide at Z 1.460, .132 m at Z 1.480 and .117 m at Z 1.500. Its lower width is 83% of ear-inclusive head width and exceeds the jaw slice width (.111 m at Z 1.520).
- 몸통 가슴 Z 1.300의 폭/깊이는 .387/.277 m, 허리 Z 1.075는 .323/.262 m입니다. 깊이/폭 비가 가슴 .716, 허리 .812로 단면이 둥글고, 전면과 후면도 거의 같은 모양입니다.
- At chest height Z 1.300, the full outer sleeve span is .629 m, 3.72 times ear-inclusive head width and 1.63 times torso width. This is a relaxed, partly abducted clothed pose, not a biacromial bone measurement. Arms extend much farther laterally than the narrow chest block implies.
- Shirt/neckline top Z 1.475; sleeve crown Z 1.432. Sleeve section centre at Z 1.375 is X ±.235/Y .002; at Z 1.150 it is X ±.287/Y .005; at cuff Z .900 it is X ±.322/Y .062. These are cross-section bounding-box centres, not recovered skeleton joint centres.
- 위팔 Z 1.150–1.225의 폭은 .117–.118 m, 깊이는 .102 m로 거의 일정합니다. 팔꿈치까지 자연스럽게 좁아지는 흐름보다 일정한 관 모양에 가깝습니다. Z 1.350 어깨의 깊이 .145 m에서 Z 1.250 깊이 .099 m로 빠르게 줄어들어 별도의 둥근 캡처럼 보입니다.
- Left/right sleeve bounds and slice centres agree within approximately .2 mm; the main defect is not asymmetric placement. The head/neck has minor genuine source asymmetry, with lower neck centre X around −.0025 m.

## 형상 문제 / Shape interpretation

1. 목 밑동이 턱보다 넓은 원뿔 형태이고, 목 중심선과 쇄골/가슴 표면이 따로 끝납니다. 표면에 작은 근육 굴곡을 추가하는 것만으로는 이런 큰 형태의 불일치를 해결하지 못합니다.
2. Torso cross sections are almost exact front/back mirrors. The chest is deepest at the centre and pinches sharply into a narrow seam at X≈.195, then expands again into the sleeve cap. At Z 1.300, front Y is .138 at X0, .084 at X .160, .044 at X .200, and .065 at X .240. The seam valley is still more than 20 mm recessed from the cap's front surface.
3. 어깨/가슴 높이의 전반적인 비율과 단면을 함께 수정해야 합니다. 중앙의 둥근 몸통, 옆에 따로 붙은 캡, 일정한 굵기의 위팔을 각각 독립 확대하는 방식은 참고 이미지의 가슴→전면 삼각근→위팔 연결을 만들지 못합니다.
4. The reference depicts a muscular but continuous chest/shoulder structure. It is perspective imagery and cannot uniquely determine centimetre values. Use its relation between chest width, deltoid volume, neck taper and arm flow as a visual target; do not assert exact human-standard dimensions from it.
5. Existing face and hands have detailed authored anatomy while the shirt silhouette lacks a corresponding chest/lat/shoulder structure. This difference amplifies the assembled appearance even when material seams are softened.

No source or runtime model was changed by this inspection. These measurements diagnose the baseline; successful correction still requires actual front/side/oblique renders, not merely a passing dimension threshold.
