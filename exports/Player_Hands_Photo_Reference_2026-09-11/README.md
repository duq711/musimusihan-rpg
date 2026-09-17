# 사진을 참고해 다시 만든 플레이어 양손

첨부한 손바닥·손등 사진을 기준으로 기존 반장갑을 맨손으로 바꾸고, 손가락의 가늘어지는 단면과 관절 폭, 엄지 연결, 손바닥 살집, 얇은 손톱과 손목 연결을 다듬었습니다. 팔 위쪽의 보호대와 소매는 유지합니다. 사진은 형태·색의 참고 자료이며, 단일 사진으로 실제 손을 정밀 스캔한 모델은 아닙니다.

피부색은 손바닥 중앙과 손가락별 관절 좌표에 맞춘 원본 사진을 기존 피부 재질에 최대 65% 혼합합니다. 피부 밖이나 투영 경계는 기존 색으로 부드럽게 전환합니다. 큰 손금, 마디 주름과 미세 피부결은 Blender 절차적 재질에서 tangent normal로 베이크합니다. 원본 사진 파일은 수정하지 않습니다.

손톱은 곡면을 따라가는 촘촘한 삼각형으로 구성하고, 정점뿐 아니라 삼각형 내부까지 피부와의 간격을 확인해 피부가 손톱 위로 비치는 문제를 보정했습니다. 손목에서는 피부 끝과 겹치던 연결면의 바깥쪽만 최대 0.35mm 조정했습니다. 이 표면 보정은 Blender 기준 y=−25~0mm 구간에 한정하며 피부 형상·관절 교정과 팔 쪽 연결부는 유지합니다. 이후 주먹 자세에서 확인된 손목 벌어짐은 아래의 국소 가중치 보정으로 해결하도록 수정했습니다.

## 파일과 Blender 사용

작업 원본의 최종 출력 위치는 `mac_output/final_04/`이며, 배포 묶음에서는 아래 파일이 최상위에 놓입니다.

| 파일 | 내용 |
|---|---|
| `bilateral_hands_reference.blend` | 편집 가능한 양손·리그·재질, 이미지 내장 |
| `left_hand_reference.glb`, `right_hand_reference.glb` | 각 손의 리그·교정 모프·PBR 이미지를 내장한 독립 파일 |
| `reference_hands_basecolor.png` | 양손 공용 4096×4096 sRGB 색 atlas |
| `reference_hands_normal.png` | 양손 공용 4096×4096 tangent normal atlas |
| `reference_hands_roughness.png` | 양손 공용 4096×4096 거칠기 atlas; glTF에서는 G 채널 |
| `dorsum.png`, `palm.png`, `side.png` | 실제 Blender 손등·손바닥·측면 렌더 |
| `dorsum_closeup.png`, `palm_closeup.png` | 피부와 손금 근접 렌더 |
| `reference_palm_and_dorsum.png` | 같은 오른손 모델을 양면으로 보여주는 사진 비교 구도 |

`.blend`의 기본 장면은 `Bilateral_Reference_Review`입니다. 양손을 보는 카메라와 재질 미리보기가 설정되어 있으며 F12로 다시 렌더할 수 있습니다. `Photo_Reference_Palm_And_Dorsum`은 사진과 비슷한 구도의 별도 검토 장면입니다. 흰 배경의 검토 조명과 실제 게임 조명은 다릅니다.

각 손은 `wrist`와 `thumb/index/middle/ring/little`의 `0/1/2`로 이루어진 16본, 피부의 `Joint_<digit>_<0/1/2>` 교정 15개를 사용합니다. 기본값은 열린 손, 교정값 0입니다. Blender에서 한 마디를 직접 확인하려면 해당 본의 로컬 X를 음수로 회전하고 같은 이름의 교정값을 굽힘 각도의 절댓값/최대각(0~1)으로 맞춥니다. 최대각은 엄지 60°/70°/80°, 나머지 손가락 90°/110°/80°이며, 자동 드라이버가 있다고 가정하지 마세요. 손톱은 각 끝마디 본을 따라갑니다. 원래 본 이름·휴지 자세·손목 기준점은 유지합니다. 손목 유연 전이는 손에서 팔로 향하는 Godot z 기준 26mm에서 시작하고 75mm에서 팔을 완전히 따릅니다(`wrist_flex_version=1`). 피부 끝 20.697mm보다 5.3mm 뒤에서 변형을 시작하여 피부와 겹치는 연결면을 고정하고, 강하게 굽혔을 때의 안쪽 압축 여유도 확보합니다.

피부의 손목 가중치는 같은 Godot z 기준 10mm 이하에서 원본 그대로이며, 10~18mm 구간에서 smoothstep으로 모든 손가락 본의 영향을 줄여 `wrist`로 옮깁니다. 18mm 이상은 `wrist`만 따릅니다. 변경 정점은 왼손 441개, 오른손 442개이며 손가락 쪽 가중치는 그대로입니다. 피부 형상·법선·UV·15개 교정·휴지 자세는 수정하지 않았고, 고정되는 손목 구역의 교정 변위는 실제 측정값 0입니다.

중립 Blender 렌더 6장은 `final_02`의 실제 렌더를 같은 해시로 재사용했습니다. `metadata_update_report.json`은 중간 `final_03`의 시작점 변경을, `weight_update_report.json`은 최종 `final_04`의 국소 가중치 및 시작점 28→26mm 변경을 기록합니다. 최종 형상·UV·교정·재질·이미지·포즈·카메라·조명·월드는 동일하며, 가중치 변경 전후 중립 상태의 실제 평가 정점 위치 차이는 최대 14.9nm, 단위 법선 벡터 차이는 4.36×10⁻⁶입니다. 전체 가중치가 동일하다는 의미는 아닙니다. GLB는 승인된 WEIGHTS와 시작점 속성만 바뀌었으며 다른 BIN 바이트는 동일합니다. 이 중립 렌더는 변경된 게임 손목 변형의 검증을 대신하지 않습니다.

게임에서는 기존 상세 손(`detailed`) 프로파일과 테스트룸의 손·손가락 시험에 연결합니다. 실제 적용 파일, 관절·손목·활·상자 동작과 완료된 화면 검토 결과는 `validation_summary.json` 및 연결된 로그·캡처를 확인하세요. 최종 검증 판정과 남은 외형 한계는 그 요약 보고서와 아래 최종 검토 상태에 기록했습니다.

## 재현과 독립 검증

Blender 5.2.1 LTS의 백그라운드 실행, NumPy와 Pillow가 있는 Python, C++17 컴파일러가 필요합니다. 베이크·padding·내보내기 도구는 `tools/`에 들어 있습니다. 현재 padding 스크립트는 `/usr/bin/clang++`를 사용하므로 아래 명령은 Mac 기준입니다. 다른 환경에서는 해당 컴파일러 경로를 먼저 맞춰야 합니다. 특정 사용자 홈의 기본 Python 경로에 의존하지 않도록 `--padding-python`을 명시합니다.

형상 전체를 다시 만드는 입력은 이전 납품의 `player_hands_realism_20260911/mac_output/iteration_04/`입니다. 그 안의 `bilateral_hands_realistic.blend`와 좌우 `*_hand_realistic.glb`는 외부 기준 자료이며 새 배포 묶음에 중복 포함하지 않습니다. 최종 베이크와 독립 비교에는 승인된 `geometry_06/bilateral_hands_reference_geometry.blend` 및 같은 폴더의 `geometry_report.json`도 필요합니다. 보고서에 기록된 원본·형상 SHA와 실제 파일이 일치해야 합니다. `validation/geometry_report.json`만으로는 형상 기준 파일을 대신할 수 없습니다.

아래는 형상 생성 → 손톱·손목 표면 보정 → 베이크 → 손목 메타데이터 보정 → 손목 가중치·시작점 보정 → 독립 검증의 전체 재현 순서입니다. 변수는 실제 경로로 바꾸고 모든 출력에는 서로 다른 새 폴더를 지정하세요. `repair_reference_nails.py`는 기본 형상 결과 또는 보존된 `geometry_03`에 한 번만 적용합니다. `patch_wrist_flex_metadata.py`는 시작점이 14mm인 중간 결과를 받아, 새 형상 기준과 새 납품의 시작점만 28mm로 바꿉니다. `repair_wrist_skin_weights.py`는 그 28mm 중간 결과에서 10~18mm 가중치 전이와 최종 시작점 26mm를 적용합니다. 각 보정은 해당 입력에 한 번만 실행하고 이미 보정된 결과에 반복 적용하지 마세요.

```sh
HAND_BLENDER='/Applications/Blender.app/Contents/MacOS/Blender'
HAND_PYTHON='/absolute/path/to/python-with-numpy-and-pillow'
HAND_PACKAGE='/absolute/path/to/Player_Hands_Photo_Reference_2026-09-11'
HAND_SOURCE='/absolute/path/to/player_hands_realism_20260911/mac_output/iteration_04'
HAND_RAW_GEOMETRY='/absolute/path/to/new-hand-geometry'
HAND_FIXED_GEOMETRY='/absolute/path/to/new-hand-geometry-fixed'
HAND_BAKED='/absolute/path/to/new-hand-baked'
HAND_META_GEOMETRY='/absolute/path/to/new-hand-geometry-meta28'
HAND_META_FINAL='/absolute/path/to/new-hand-final-meta28'
HAND_GEOMETRY='/absolute/path/to/new-hand-geometry-final'
HAND_NEW='/absolute/path/to/new-hand-final'

"$HAND_BLENDER" --background --factory-startup --threads 2 --python-exit-code 1 \
  --python "$HAND_PACKAGE/tools/build_reference_hands.py" -- \
  --phase geometry --source "$HAND_SOURCE/bilateral_hands_realistic.blend" \
  --output "$HAND_RAW_GEOMETRY"

"$HAND_BLENDER" --background --factory-startup --threads 2 --python-exit-code 1 \
  --python "$HAND_PACKAGE/tools/repair_reference_nails.py" -- \
  --source "$HAND_RAW_GEOMETRY/bilateral_hands_reference_geometry.blend" \
  --output "$HAND_FIXED_GEOMETRY"

"$HAND_BLENDER" --background --factory-startup --threads 2 --python-exit-code 1 \
  --python "$HAND_PACKAGE/tools/build_reference_hands.py" -- \
  --phase material \
  --source "$HAND_FIXED_GEOMETRY/bilateral_hands_reference_geometry.blend" \
  --output "$HAND_BAKED" --padding-python "$HAND_PYTHON"

"$HAND_BLENDER" --background --factory-startup --threads 2 --python-exit-code 1 \
  --python "$HAND_PACKAGE/tools/patch_wrist_flex_metadata.py" -- \
  --geometry-source "$HAND_FIXED_GEOMETRY" --geometry-output "$HAND_META_GEOMETRY" \
  --final-source "$HAND_BAKED" --final-output "$HAND_META_FINAL"

"$HAND_BLENDER" --background --factory-startup --threads 2 --python-exit-code 1 \
  --python "$HAND_PACKAGE/tools/repair_wrist_skin_weights.py" -- \
  --geometry-source "$HAND_META_GEOMETRY" --geometry-output "$HAND_GEOMETRY" \
  --final-source "$HAND_META_FINAL" --final-output "$HAND_NEW"

"$HAND_BLENDER" --background --factory-startup --threads 2 --python-exit-code 1 \
  --python "$HAND_PACKAGE/tools/verify_reference_hands.py" -- \
  --source-dir "$HAND_SOURCE" \
  --geometry-report "$HAND_GEOMETRY/geometry_report.json" \
  --output-dir "$HAND_NEW" \
  --support-dir "$HAND_PACKAGE/tools/verification_support"
```

두 후처리 단계는 다시 베이크하거나 렌더하지 않습니다. 메타데이터 단계는 GLB BIN 전체를 보존하며, 가중치 단계는 허용된 WEIGHTS 바이트 범위를 제외한 BIN 보존을 검사합니다. 수정 대상 밖의 가중치, 형상·이미지·교정·리그·표시 설정을 비교하고, 원본 PNG와 중립 렌더를 동일 해시로 새 출력에 복사합니다. 승인된 `geometry_06`에서 재베이크만 할 때는 그 `.blend`를 material 입력으로 사용하고, 이미 가중치 보정과 26mm 시작점이 적용되어 있으므로 두 후처리 단계를 반복하지 않습니다. Blender 버전이나 UV packing 차이로 재현 결과의 해시가 기존 납품과 달라질 수 있으므로 새 결과에도 별도 검증과 게임 화면 검토가 필요합니다.

이전 원본과 납품은 덮어쓰지 않습니다. 보존 대상 해시는 `validation/preserved_artifacts.json`, 배포 파일 해시는 `FILE_MANIFEST.json`에 기록합니다. `runtime_snapshot/`은 검토 당시 게임 코드의 참고 사본이며 독립 실행 가능한 전체 Godot 프로젝트를 대신하지 않습니다.

## 최종 검토 상태

Blender 독립 검사와 관련7개 Godot 자동 검사, 실제 GPU18장 상태 검사를 통과했고 전체 화면을 직접 검토했습니다. 주먹에서 벌어지던 틈은 해결됐습니다. 강한 손목 굽힘의 피부/Cuff 경계에는 얕은 단차가 남아 있으며 `validation/visual_review.json`에 명시합니다. 사진을 참고한 게임 모델이며 사진 실사 스캔과 동일하다고 주장하지 않습니다. 최종 해시와 검사 근거는 `validation_summary.json`을 따릅니다.
