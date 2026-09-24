# 어깨 뒤 밀착 제압 / Close rear-shoulder takedown

2026-09-24. 현재 Godot 프로젝트의 실제 동작으로 촬영했습니다. 생성 이미지나 참고 영상의 재사용이 아닙니다.

- `rear_close_takedown_full.mp4`: 실제 9초/30fps/270프레임. 앞 6초는 후방 검 제압과 랙돌, 뒤 3초는 경계 중인 적의 제압 거부 확인입니다.
- `rear_sword_stab.png`, `rear_sword_hold.png`: 본편 1인칭 구도에서 실제 관통 칼끝을 확인합니다.
- `rear_sword_*_side.png`, `*_front.png`, `*_grip_side.png`, `*_head_side.png`, `*_head_front.png`: 동일한 시각·동일한 자세를 공유하는 별도 검수 카메라입니다.
- `capture_manifest.json`: 실제 피부 교차, 칼날·손목·카메라 수치, 프레임 시각, 렌더러와 원본 해시.
- `headless.log`, `render.log`, `video_decode.log`, `validation_summary.json`: 실행·검증 근거.

검사 결과: 후방 미인지 조건, 곡선 접근과 장애물 취소, 지원 검·재진입 사례, 첫 접촉 출혈, 몸통 앞뒤 관통, 고개 들기, 단일 처치·보상, 곧은 검 회수 후 랙돌, 대상 삭제 후 정리, F2 반복·초기화와 원정 보존을 통과했습니다. Vulkan 실제 화면 84장과 영상 270프레임을 저장했으며 원정·가방·커서와 촬영 중 원본을 보존했습니다. 손목의 축 차이는 동작 구간 최대 37.60도이고 칼의 횡방향 흔들림은 0.17mm 미만입니다. 해당 축 지표는 임상적인 관절각 판정이 아닙니다.

반영한 참고 특징: 첨부 Far Cry 스크린샷의 가까운 어깨 뒤 구도와 반대편으로 나온 칼날. 이번 작업에서는 원본 영상을 시청하지 않았으므로 프레임 단위 재현을 주장하지 않습니다. 기존 장검과 크리프를 유지했습니다. 칼끝은 어깨 바깥으로 보이나 참고 이미지의 큰 단검보다 가늘고 작습니다. 별도의 붙잡는 왼손이나 관통 부위의 새 상처 메시, 비명 음성은 이번 변경에 추가하지 않았습니다.

검증은 `/private/tmp/rear-close-runtime-20260924`에 원본과 해시가 같은 프로젝트 코드 복사본을 만들어 수행했습니다. iCloud 파일 읽기 지연을 피하기 위한 실행 위치이며 실제 모델과 동일한 Godot 캐시를 사용했습니다. 게임 기능은 원래 프로젝트 파일에 수정되어 있습니다. `runtime_source_match.json`에서 이번 변경 9개 코드/검사 파일 일치를 확인할 수 있습니다. 공유 중이던 다른 분야 변경은 GitHub 게시 범위에서 제외합니다.

English: Actual production takedown, live AI/physics and hidden Vulkan rendering passed both core and F2 integration checks. The nine-second video contains six seconds of the successful rear takedown and three seconds of alerted-target refusal. Eighty-four same-pose inspection PNGs and the full manifest preserve measured geometry and source hashes. The close rear-left stance exposes real steel beyond the opposite torso surface while retaining contact blood, the head-up reaction, one twist, straight extraction and blade-clear ragdoll. This implements the close-shoulder/visible-exit mechanism; the protruding longsword tip remains smaller and thinner than the reference knife. No frame-matched source-video recreation or OS hardware-input verification is claimed. Only this task’s scoped changes are published.

GitHub: `codex/rear-close-takedown-20260924`, `f1789b4a97e94819d7c41328d552f783e410e85c`. 원격 커밋과 검수 이미지·영상 85개(고유 객체 80개)의 새 다운로드 해시를 확인했습니다. / Remote commit and freshly downloaded hashes for all 85 review media files (80 unique objects) verified. See `publication_verified.json`.
