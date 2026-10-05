# 래브라도 쓰다듬기 미리보기 / Labrador petting preview

프로젝트 루트에서 `python3 tools/labrador-petting-viewer/server.py`를 실행하고 http://127.0.0.1:8773/ 을 엽니다. 머리 위에서 마우스 왼쪽 버튼을 누르고 천천히 움직이면 귀·고개·눈·짧은 털·꼬리가 반응합니다. 손 모델은 없습니다. 전체 보기/머리 가까이/다시 시작 버튼을 제공합니다.

Run the command from the project root and open the local URL. Hold the left mouse button and move slowly across the head for ear, head, eyelid, short-coat and tail reactions. No hand model is rendered.

모델은 로컬 `asset-staging/labrador-pet-20261005/export/LabradorPet_Petting.glb`를 사용합니다. 공개 코드만 받아서는 licensed model이 포함되지 않습니다. 공식 무료 원본과 제작 도구는 `docs/LABRADOR_PET_20261005.md`를 참고합니다. 서버는 이 미리보기와 모델만 loopback으로 제공합니다.

The licensed model remains local; it is not included in the public code checkpoint. See the project Labrador document for the official free source and production tools. The server exposes only this preview and its model on loopback.

`vendor/`에는 기존 프로젝트의 Three.js r170 모듈과 GLTFLoader, BufferGeometryUtils 및 MIT LICENSE를 그대로 복사했습니다. 외부 CDN 없이 동작합니다. 이 미리보기의 반응은 실제 3D skin을 쓰지만 Unity 본편/F2 인수 검증은 별도로 기록합니다.

The included Three.js r170 modules and MIT license are copied unchanged from the project's existing viewer. No CDN is required. This actual-skin browser preview is separate from native Unity/F2 acceptance.
