# 실제 Godot 모션 캡처의 검토 영상

encode_godot_review.py는 reference_sword_motion_preview.gd가 실제 Godot 렌더러에서 저장한 PNG와 capture_manifest.json을 MP4로 묶습니다. Blender 제작·렌더링을 실행하지 않습니다.

현재 Mac에서 확인한 실행 환경은 아래와 같습니다. 별도 전역 설치 없이 기존 UV 캐시의 PyAV 18.1.0, Pillow 12.3.0 및 libx264를 사용합니다. PATH 및 번들 실행 폴더에서는 독립 ffmpeg 명령을 찾지 못했습니다.

    "/Users/duq711gmail.com/.cache/uv/archive-v0/Ul3ouI3eOlPiROsy/bin/python" \
      asset-staging/reference_sword_motion_20260909/encode_godot_review.py \
      --manifest godot-game/artifacts/visual_qa/reference_sword_motion/<실제_촬영_폴더>/capture_manifest.json \
      --output godot-game/artifacts/visual_qa/reference_sword_motion/<실제_촬영_폴더>/review_01.mp4

위 명령의 촬영 폴더는 실제 완성된 결과로 바꿉니다. 캐시 환경이 삭제되었다면 PyAV와 Pillow가 이미 설치된 다른 Python 환경을 사용합니다. 스크립트가 의존성을 설치하지는 않습니다.

- 대기 → 달리기 → 도약·공중·착지 → 우측 대각 베기 → 좌측 역베기 → 상단 내려베기의 여섯 시퀀스 전체를 순서대로 표시합니다.
- 파일 누락, 중복 프레임, 잘못된 크기·시각, 실패한 캡처, 미로드 모션은 인코딩 전에 거부합니다. 선택 포즈나 플레이스홀더로 누락된 동작을 대신하지 않습니다.
- 프레임률은 캡처 manifest의 FPS를 사용하며 원본 프레임마다 정확히 한 프레임을 기록합니다. 각 마지막 시각의 프레임도 한 프레임 간격 동안 표시되므로 인코딩 구간 길이는 frame_count / fps입니다.
- 원본 PNG는 자르거나 확대하지 않고, 위쪽 80픽셀 띠에 프로젝트의 NotoSansKR-Variable.ttf Regular로 한국어 동작명·실제 Godot 캡처·원본 시각을 표시합니다. 최종 MP4만 H.264 손실 압축을 사용합니다.
- 모든 PNG와 manifest를 보존합니다. 출력 이름이 이미 있으면 중단합니다. MP4를 다시 디코딩해 전체 프레임 수·크기·시각을 검사하고 원본 PNG 해시도 다시 확인합니다.
- 함께 생성되는 review_01.encode.json에는 원본 manifest·각 PNG·완성 MP4의 SHA-256, 여섯 구간의 출력 프레임 범위와 시간이 기록됩니다. 참고 영상과의 시각적 일치 여부는 별도 실제 화면 검토 대상입니다.

새 오른팔 내려베기 한 개를 격리 검토할 때만 --single-overhead-review를 명시합니다. 이 모드는 reference_sword_overhead_review_preview.gd의 실제 94장 캡처와 미완성·관절 재생 메타데이터를 요구합니다. 1.55초 endpoint PNG는 해시와 함께 보존하고 앞의 93프레임을 60fps로 인코딩해 원본과 같은 1.55초를 유지합니다. 실행 예시는 OVERHEAD_REVIEW_CONTRACT.md에 있습니다. 단일 검토 성공은 여섯 시퀀스나 여덟 클립 전체 납품 성공을 뜻하지 않습니다.
