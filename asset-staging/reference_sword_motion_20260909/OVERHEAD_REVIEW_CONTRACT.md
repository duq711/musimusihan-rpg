# 단일 내려베기와 오른팔 관절 검토

이번 파일은 8개 동작 중 내려베기 1개를 고치는 중간 검토 자료입니다. 완성 게임 데이터와 별도로 보관하며 production motion_manifest.json에 복사하지 않습니다. 공식 최소 구조는 overhead_review.schema.json입니다.

## Windows 납품 필드

- schema_version: 1
- status: authored_windows_review_output
- reference_video_url: https://youtu.be/sU7jk2OQlgc
- source, coordinate_system, camera, provenance: 기존 원본 보존·카메라 로컬 계약과 동일합니다. 카메라는 수직 시야각 76도, 16:9, 고정입니다.
- clips: overhead 하나만 담습니다. 기존 clip 구조의 sword와 shield 두 절대 피벗 트랙, attack timing, reference_segments를 포함합니다. duration_seconds는 1.55, loop는 false이며 최소 60Hz로 샘플합니다.
- right_arm: 각 원소에 time_seconds와 shoulder, elbow, wrist를 넣는 배열입니다. 세 관절은 각각 숫자 세 개의 xyz 배열이며 Godot 카메라 로컬·미터 단위입니다. 양 피벗 트랙과 같은 샘플 수·시각을 사용합니다.
- artifacts, notes: 선택 필드입니다. 실제 Blender 원본·재오픈 검사·프레임 보고서는 제작 결과로 함께 보존합니다.

right_arm의 숫자는 실제 새 Windows Blender 액션을 평가한 관절 위치여야 합니다. 팔꿈치를 피벗 궤적에서 Mac이 추정하거나, 없는 관절 데이터를 기존 solver로 대체하지 않습니다. 별도 part basis·cuff track·새 rig 구조는 이번 최소 계약에 포함하지 않았습니다.

## 실제 Godot 검토 경로

새 하네스는 기존 격리 SubViewport와 실제 DungeonPlayer·원본 장갑/검·소매를 재사용합니다. 외부 검토 JSON에서 0~1.55초를 직접 읽으며 combat 단계 시간에 맞춰 다시 매핑하지 않습니다. 공격·피해·기력·실제 입력을 진행하지 않는 authored-time 검토라는 사실을 capture_manifest.json에 기록합니다.

각 프레임에서 sword/shield 피벗을 적용하고 기존 장비 파지를 맞춘 뒤, 실제 sword_long_grip_visual의 fit_arm에 카메라 월드 변환으로 옮긴 authored shoulder/elbow를 전달합니다. 기존 손·검 파지는 고정하고 실제 소매 메시를 연결합니다. 왼팔은 현재 production 방패 fitting을 유지하며, 오른팔의 새 관절 검토 범위와 구분합니다.

검사 임계값은 다음과 같으며 시각적 품질 승인 기준 전체를 대신하지 않습니다.

- 실제 손목과 authored wrist의 차이: 1mm 미만. 실제 손목은 T_sword * REST_WRIST입니다.
- 실제 어깨·팔꿈치와 authored 관절 fitting 오차: 1mm 미만.
- 위팔 0.34m, 팔뚝 0.26m: 각각 ±1% 이내.
- 손·검 접촉, 유한 변환, 원본 메시 resource·파일 해시, 카메라·게임 시계·자원·원정 보존.

임계값을 넘으면 프레임·측정값을 기록하고 실패로 보고합니다. 캡처 성공도 quality_approval=false이며 실제 팔·손목·화면 궤적 비교 후 승인이 필요합니다. 기존 완성 데이터 loader와 8클립 시험은 그대로 유지합니다.

## 실행

먼저 새 하네스의 자동 검증을 내부 headless 실행기로 확인합니다. 환경 변수가 없으면 구조·격리·누락 거절만 검사하며 새 Windows 데이터 검증을 했다고 표시하지 않습니다. 실제 데이터 경로를 지정하면 94개 시각의 실제 팔 연결도 함께 검사합니다.

    OVERHEAD_REVIEW_MANIFEST="/absolute/path/overhead_review.json" \
      godot-game/tests/run_headless_tests.sh reference_sword_overhead_review

그다음 검증된 숨김 embedded 경로로 촬영합니다. 창·커서·입력·오디오를 사용하지 않으며 Mac Blender 작업은 실행하지 않습니다.

    OVERHEAD_REVIEW_MANIFEST="/absolute/path/overhead_review.json" \
    OVERHEAD_REVIEW_ITERATION="overhead_joint_review_01" \
      godot-game/tests/run_embedded_preview.sh reference_sword_overhead_review_preview.gd

결과는 godot-game/artifacts/visual_qa/reference_sword_overhead_review/의 새 반복 폴더에 저장됩니다. 60Hz에서 0초와 1.55초 양 끝을 포함한 PNG 94장과 실제 측정 보고서가 생성됩니다. 정확히 1.55초의 60fps 영상은 93프레임으로 인코딩하고, 마지막 1.55초 endpoint PNG는 검증 자료로 보존합니다.

실제 촬영이 통과한 뒤 기존 인코더의 명시적 단일 검토 모드를 사용합니다. 이 모드는 오른팔 관절 재생·미완성 납품·시간 재매핑 없음 메타데이터를 요구하며, 기존 여섯 클립 완성 검증 모드를 대체하지 않습니다.

    "/Users/duq711gmail.com/.cache/uv/archive-v0/Ul3ouI3eOlPiROsy/bin/python" \
      asset-staging/reference_sword_motion_20260909/encode_godot_review.py \
      --single-overhead-review \
      --manifest godot-game/artifacts/visual_qa/reference_sword_overhead_review/overhead_joint_review_01/capture_manifest.json \
      --output godot-game/artifacts/visual_qa/reference_sword_overhead_review/overhead_joint_review_01/review_01.mp4
