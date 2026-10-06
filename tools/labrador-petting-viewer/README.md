# 래브라도 미리보기 / Labrador previews

프로젝트 루트에서 `python3 tools/labrador-petting-viewer/server.py`를 실행하고 http://127.0.0.1:8773/ 을 엽니다. 머리 위에서 마우스 왼쪽 버튼을 누르고 천천히 움직이면 귀·고개·눈·짧은 털·꼬리가 반응합니다. 손 모델은 없습니다. 전체 보기/머리 가까이/다시 시작 버튼을 제공합니다.

Run the command from the project root and open the local URL. Hold the left mouse button and move slowly across the head for ear, head, eyelid, short-coat and tail reactions. No hand model is rendered.

모델은 로컬 `asset-staging/labrador-pet-20261005/export/LabradorPet_Petting.glb`를 사용합니다. 공개 코드만 받아서는 licensed model이 포함되지 않습니다. 공식 무료 원본과 제작 도구는 `docs/LABRADOR_PET_20261005.md`를 참고합니다. 서버는 이 미리보기와 모델만 loopback으로 제공합니다.

The licensed model remains local; it is not included in the public code checkpoint. See the project Labrador document for the official free source and production tools. The server exposes only this preview and its model on loopback.

`vendor/`에는 기존 프로젝트의 Three.js r170 모듈과 GLTFLoader, BufferGeometryUtils 및 MIT LICENSE를 그대로 복사했습니다. 외부 CDN 없이 동작합니다. 이 미리보기의 반응은 실제 3D skin을 쓰지만 Unity 본편/F2 인수 검증은 별도로 기록합니다.

The included Three.js r170 modules and MIT license are copied unchanged from the project's existing viewer. No CDN is required. This actual-skin browser preview is separate from native Unity/F2 acceptance.

## 걷기와 달리기 / Walk and Run

같은 서버의 http://127.0.0.1:8773/locomotion/ 에서 걷기·달리기를 선택합니다. 보통 속도/0.5배속, 옆에서/비스듬히 시점, 일시정지, 시간 이동 슬라이더로 발 디딤과 반복 연결을 확인할 수 있습니다. 바닥 이동은 각 클립의 `speed_m_s`와 재생 배속에 맞춰 격자를 움직이며 버튼으로 제자리 보기와 전환합니다.

Select Walk or Run at `/locomotion/`. Normal/half speed, side/three-quarter views, pause and the seek slider show paw contact and loop boundaries. Moving ground uses each clip's nominal speed and playback rate and can be disabled.

2026-10-06 달리기 수정은 `asset-staging/labrador-gallop-20261006/export/`의 `LabradorPet_Gallop.glb`와 `gallop-manifest.json`을 사용합니다. `locomotion-source.json`이 최종 채택한 에셋을 선택하며 서버를 다시 시작하면 적용됩니다. 설정이 없으면 이전 `asset-staging/labrador-pet-20261005/export/`의 locomotion 파일을 사용합니다. 기존 쓰다듬기 모델·care·Walk와 이전 제작본은 보존합니다. Unity F2의 `래브라도 · 걷기 / 달리기 모션`은 제자리 게임용 클립 검사이며 1/2 또는 화면 버튼으로 전환합니다.

The 2026-10-06 gallop correction uses the new task's combined GLB and manifest. `locomotion-source.json` selects accepted assets at server startup; without that configuration, the previous locomotion bundle is used. Original petting, care, Walk and prior production remain preserved. Native F2 uses actual in-place game clips with 1/2 keys or buttons; native acceptance is recorded separately. See `docs/LABRADOR_GALLOP_20261006.md` for the reference-based correction.

2026-10-06 영상 기준 최종 질주는 `asset-staging/labrador-sprint-20261006/export/`의 `LabradorPet_Sprint.glb`와 `sprint-manifest.json`을 사용합니다. 0.70초 주기, 2.3472m/s 기준 이동이며 참고 영상의 속도 자막을 게임 속도로 사용하지 않습니다. 정상·반속도·비스듬한 시점 12초 영상과 새 Unity 인수는 `docs/LABRADOR_SPRINT_20261006.md`에 기록합니다.

The latest video-reference sprint uses the Sprint bundle selected in `locomotion-source.json`: a 0.70s cycle and nominal 2.3472m/s. Reference speed overlays are not game speed. The new 12s reel and fresh native acceptance are documented in the Sprint handoff.
