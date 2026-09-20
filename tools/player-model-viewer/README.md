# 플레이어 360° 모델 뷰어 / Player 360° model viewer

현재 게임의 `godot-game/assets/3d/player/gravebound_player.glb`를 직접 불러오는 로컬 제작 검수 도구입니다. 모델 복사본이나 정지 이미지가 아니며 게임 데이터는 수정하지 않습니다. 브라우저용 조명을 사용하므로 Godot 렌더와 밝기는 다를 수 있습니다.

English: A local review tool that loads the current game GLB directly, with no model copy or game-state changes. Browser lighting may differ from Godot.

프로젝트 루트에서 실행 / Run from project root:

```sh
python3 tools/player-model-viewer/server.py --port 8768
```

브라우저에서 http://127.0.0.1:8768 을 엽니다. 서버는 localhost에만 연결하며 종료는 Ctrl+C입니다. 모델 수정 후 브라우저를 새로고침하면 최신 파일이 적용됩니다.

English: Open http://127.0.0.1:8768. The server binds to localhost only; stop with Ctrl+C. Refresh after asset edits to load the latest model.

- 왼쪽 드래그: 360° 회전 / Left drag: free orbit.
- 휠: 확대·축소 / Wheel: zoom.
- 오른쪽 드래그 또는 Ctrl+왼쪽 드래그: 이동 / Right drag or Ctrl+left drag: pan.
- 손 확대, 정면·후면·측면, 전신 맞춤, 자동 회전 / Hand focus, preset views, fit and auto-rotation.
- 터치: 한 손가락 회전, 두 손가락 확대·이동 / Touch: one finger orbit, two fingers zoom/pan.

Three.js 0.170.0의 필요한 파일만 vendor에 고정 포함했습니다(MIT, vendor/LICENSE). 런타임 외부 CDN 요청은 없습니다.

English: Required Three.js 0.170.0 files are vendored under MIT (vendor/LICENSE), with no external CDN requests at runtime.

검증 / Validation: Codex 실제 브라우저에서 현재 모델 로드, 드래그 회전, 휠 확대·축소, 손 확대 및 전신 맞춤을 확인했습니다. 양손을 안쪽으로 돌린 게임 모델 SHA256: d25370488882606be2f87159576a6a6b45fa00bda1606cb39a6ebd44769e9b0c. 범용 라이브러리의 오른쪽 드래그 이동 경로는 코드에서 확인했습니다.

English: Verified loading, drag orbit, wheel zoom, hand focus and full-body reset in the live Codex browser. Right-drag pan uses the library's standard controls and was checked in code.
