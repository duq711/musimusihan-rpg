# 크리프 절단 연속 영상 / Continuous Creep dismemberment video

2026-09-18 · MacBook · Godot 4.7 embedded Vulkan Forward+.

[18초 영상 재생 / Play the 18-second video](creep_dismemberment.mp4)

- 0–6초: 오른팔을 두 번 타격해 절단한 뒤 남은 공격으로 전투를 계속한다.
- 6–12초: 왼다리를 절단한 뒤 절반 속도로 추적하고 공격한다.
- 12–18초: 머리를 절단하면 사망하고 몸체가 래그돌로 쓰러진다.

The three six-second sequences show right-arm loss with continued combat, left-leg loss with slow pursuit, and decapitation with death/ragdoll.

게임에 설치된 크리프 모델·재질·애니메이션·부위 피해·전투·물리 코드를 격리된 검수 장면에서 실행했다. 시험 스크립트가 실제 타격 함수를 호출하며, 화면 밖 시험 대상에 공격이 접촉한다. 던전에서 플레이어가 직접 검을 휘두르는 1인칭 녹화는 아니다. 생성 이미지나 정지 사진을 연결한 영상이 아니다.

The installed creature and production damage, AI, animation and physics code run in an isolated inspection scene. The harness calls real hit functions and receives attacks through an off-screen test target. This is not a first-person dungeon recording, generated imagery or a slideshow.

## 검증 / Validation

- 960×540, 15fps, H.264, 무음, 18.00초. 실제 GPU 프레임 270장을 순서대로 인코딩했다. 프레임 보간이나 복제는 사용하지 않았다.
- 물리는 60Hz이며 매 녹화 프레임 사이 정확히 4틱 진행했음을 검사했다. `render_manifest.json`에 270개 상태와 원본 해시, 결과가 있다.
- 팔·다리 절단 후 각각 체력 46과 후속 공격 접촉 2회가 기록됐다. 머리는 체력 0, 사망·래그돌로 전환됐다.
- `headless.log`: `creep_dismemberment` 검사 통과. `render.log`: 세 경우의 GPU 캡처 통과. `decode.log`: MP4 전체 270프레임 디코딩 통과.
- 원정 상태·커서·원본 파일 해시를 보존했다. 검증이 실행한 Godot 및 절전 방지 프로세스는 종료됐으며 기존 사용자 편집기는 그대로 두었다.
- 팔 분리·남은 팔 공격·다리 이동의 전신 구도·머리 절단 후 자세를 실제 프레임으로 확인했다. 다리 검수 카메라를 뒤로 옮겨 마지막에도 전신이 들어오게 했다.

All 270 GPU frames were encoded in order without interpolation or duplication. The 60Hz simulation advances exactly four ticks per 15fps frame. Headless checks, all three GPU cases and full MP4 decoding passed. Arm/leg cases retain 46 HP and register two subsequent attack contacts each. Source hashes, cursor and expedition state remained unchanged; only the existing user editor was left running.

`video_validation.json`에는 영상 SHA-256과 각 원본 프레임 해시가 있다. 렌더 원본은 `/private/tmp/creep-dismemberment-video_01/frames/`에 있으며 재생성 가능한 중간 JPEG는 저장소에 올리지 않는다.

The validation JSON records the video and source-frame SHA-256 hashes. Intermediate JPEGs remain in the temporary capture directory and are not published.

## 촬영 방법과 한계 / Capture and limits

```sh
CREEP_DISMEMBERMENT_VIDEO=1 \
CREEP_DISMEMBERMENT_QA_ITERATION=video_01 \
GODOT_PREVIEW_TIMEOUT_SECONDS=600 \
/usr/bin/caffeinate -i ./godot-game/tests/run_embedded_preview.sh creep_dismemberment_preview.gd
```

반복 실행 시 새 `CREEP_DISMEMBERMENT_QA_ITERATION` 이름을 사용한다. 기본 모드는 기존처럼 선택 PNG만 저장하며 `CREEP_DISMEMBERMENT_VIDEO=1`에서만 연속 프레임을 만든다. 매 프레임 `UPDATE_ONCE`로 렌더링한다.

Use a fresh capture tag on each run. The default remains selected PNG stills; the video environment variable enables a continuous sequence with one render per state.

이전 영상 시도의 정지는 macOS 전원 로그와 프레임 저장 시간을 비교해 절전 진입으로 확인했다. 2026-09-18 01:31:47–01:47:53의 966초 절전이 프레임 사이 964초 공백과 일치했다. 이번에는 촬영 프로세스가 실행되는 동안만 `caffeinate -i`를 사용했으며 지속 설정은 바꾸지 않았다.

The earlier capture stall matched a 966-second macOS sleep interval, rather than slow frame encoding. This run used a scoped idle-sleep assertion without changing persistent settings.

다리 손실 동작에는 기존 클립과 이동·접지 보정을 사용해 뛰듯 보이는 부분이 있다. 별도의 절뚝임/포복 클립은 아직 없으며 목 절단면은 평평한 단색이다. 이번 머리 사례는 영상 끝에서 `settled` 상태로 안정화됐다. 단일 절단 메시 처리 시간은 이번 캡처에서 19–34ms였다. 게임 기능 자체는 이번 영상 작업에서 변경하지 않았다.

Leg loss still uses existing clips with speed/grounding adjustments and can look like hopping, not a bespoke limp/crawl animation. The neck cap remains flat and uniformly colored. This head-case capture reaches the `settled` phase by its end. One-time severance baking took 19–34ms. No gameplay behavior changed in this capture task.
