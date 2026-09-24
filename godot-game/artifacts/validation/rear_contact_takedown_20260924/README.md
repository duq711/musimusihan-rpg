# 등 바로 뒤 밀착 제압 / Hand-free close rear takedown

2026-09-24. 실제 프로젝트의 후방 검 제압을 수정해 Godot Vulkan 렌더러로 촬영했습니다.

- `rear_contact_takedown_full.mp4`: 9초, 30fps, 270프레임. 앞 6초는 후방 제압·회수·랙돌, 뒤 3초는 경계 중인 적의 제압 거부입니다.
- `rear_sword_stab.png`, `rear_sword_twist_mid.png`, `rear_sword_hold.png`: 파지 손과 손잡이가 완전히 시야 밖으로 나간 최종 1인칭 구도입니다.
- `*_side.png`, `*_grip_side.png`, `*_front.png`: 같은 실제 자세의 별도 검수 시점입니다. 손은 실제 손잡이를 쥐고 있으며 표시를 끄지 않았습니다.
- `capture_manifest.json`, `validation_summary.json`, `headless.log`, `render.log`, `video_decode.log`, `runtime_source_match.json`: 실행·피부 교차·관절·원정 보존·원본 해시 근거입니다.

실제 원인은 몸의 접근 이후에도 눈이 뒤쪽에 남아 있어 장갑·손잡이가 크게 보인 것이었습니다. 찌르기 시 눈을 추가 45cm 전진시키고 팔 기준점을 반대로 보정했습니다. 실제 손·검의 월드 접촉과 팔 길이는 유지하며 깊은 찌르기·비틀기 동안 파지 손이 화면 밖에 놓입니다. 회수 때 부드럽게 뒤로 돌아옵니다. 손 표시를 끄거나 FOV를 바꾸지 않았습니다.

핵심 제압과 실제 F2 통합 검사 2종 통과. 실제 9초/270프레임과 84개 검수 PNG를 저장하고 주요 PNG 7장, 영상 JPG 표본 12장을 독립적으로 열어 확인했습니다. 접촉 단계의 카메라–실제 피부 거리는 16.5–18.6cm이며 시점 이동선은 피부를 통과하지 않습니다. 파지 관절 17개는 모두 화면 밖이고 실제 장갑·손잡이도 깊은 접촉 화면에서 보이지 않습니다. 반대편 실제 칼끝의 가리지 않은 길이는 960px 화면 기준 약 31–69px입니다. 기존 첫 접촉 출혈, 머리 들기, 한 번의 비틀기, 직선 회수, 검이 빠진 뒤 랙돌, 단일 사망·보상, 장애물 취소와 시험 원정 복원을 유지했습니다.

참고는 사용자 첨부 Far Cry 화면 `1b1c4f8c…`와 수정 대상인 이전 게임 화면 `d5e0cf5b…` 두 장을 실제로 열어 비교했습니다. 원본 영상 재현을 주장하지 않습니다. 기존 장검·크리프를 유지하므로 반대편 칼끝은 참고의 큰 단검보다 좁고 작습니다. 이 변경은 새 피·상처 에셋이나 비명 음향 제작을 포함하지 않습니다. OS 하드웨어 조작 검증은 미실시이며 입력은 실제 E 동작 API·F2 경로로 검사했습니다.

English: The prior stance left the eyes behind the action, keeping the glove and hilt prominent. A smooth extra 45cm forward eye lean now follows the thrust, compensated at the arm anchor so real grip/contact and arm lengths remain. The gripping hand and hilt are outside the first-person image at deep contact and twist, with a smooth retreat on extraction. Both core/F2 suites and actual 9-second/270-frame Vulkan validation passed; seven key stills and twelve video samples were independently inspected. Actual skin clearance is 16.5–18.6cm without a skin-crossing eye segment, and real far-side steel remains visible. No hand hiding, FOV change or compositing. Existing contact/reaction/death behavior is retained. The longsword's narrow tip remains smaller than the reference knife; source-video timing and OS hardware input were not validated.

검증 실행 위치는 iCloud 읽기 지연을 피한 `/private/tmp/rear-close-runtime-20260924`입니다. 실제 에셋·Godot 캐시를 공유하고 변경한 코드/검사 9개는 원본과 해시가 같습니다. 실제 변경은 원래 프로젝트에 적용했습니다. 다른 진행 중 작업은 게시 범위에서 제외합니다. / Validation used a matching local runtime copy with the real assets/cache; unrelated ongoing changes are excluded from publication.

GitHub: `codex/rear-contact-takedown-20260924`, `635a6b1b7b1f1c5e89627e0c0bd76adc3cc4e15c`. 원격 커밋 일치와 이미지·영상 85개(고유 객체 80개)의 새 다운로드 SHA-256을 확인했습니다. / Remote commit plus fresh-download SHA-256 verification passed for all 85 media files (80 unique objects).
