# 플레이어 의상 360° 뷰어 / Player outfit 360° viewer

현재 화면은 게임의 `godot-game/assets/3d/player/medival_outfit.glb`에 들어 있는 의상 메시 5개만 불러옵니다. 얼굴·신체·손·부츠가 들어 있는 기존 플레이어 GLB는 뷰어에서 불러오지 않습니다. 원본 제작 에셋은 복구할 수 있도록 보존하며 게임에서는 해당 메시를 숨깁니다. 브라우저 조명은 Godot와 다를 수 있습니다.

English: The viewer loads only the five clothing meshes in the production `medival_outfit.glb`. It does not load the former player GLB containing the face, body, hands, and boots. Source assets are retained for recovery, while the game hides those meshes. Browser lighting can differ from Godot.

프로젝트 루트에서 실행 / Run from the project root:

```sh
python3 tools/player-model-viewer/server.py --port 8769
```

`http://127.0.0.1:8769/`에서 확인합니다. 서버는 localhost에만 연결하며 Ctrl+C로 종료합니다. 에셋을 수정했다면 새로고침하세요.

English: Open `http://127.0.0.1:8769/`. The server binds to localhost only; stop it with Ctrl+C. Refresh after asset edits.

- 왼쪽 드래그: 360° 회전 / Left drag: orbit.
- 휠: 확대·축소 / Wheel: zoom.
- 오른쪽 드래그 또는 Ctrl+왼쪽 드래그: 이동 / Right drag or Ctrl+left drag: pan.
- 정면·후면·측면, 상의·허리·바지 확대, 전체 맞춤, 형태 확인, 자동 회전 / Preset views, garment focus, fit, neutral shape shading, and auto-rotation.
- 터치: 한 손가락 회전, 두 손가락 확대·이동 / Touch: one-finger orbit, two-finger zoom and pan.

이 뷰어는 의상의 정적 형태를 보여줍니다. 이동할 때 옷이 흔들리는 효과는 실제 게임의 F2 테스트룸에서 확인합니다. 사용한 Three.js 0.170.0 파일은 `vendor/`에 고정 포함되어 있으며 외부 CDN을 요청하지 않습니다.

English: The browser shows the static outfit; inspect movement-driven cloth motion in the game's F2 test room. Required Three.js 0.170.0 files are vendored, with no external CDN request.

이전 인체 비율·자세 작업 기록은 `asset-staging/`의 각 검증 문서에 남아 있습니다. 현재 뷰어는 몸을 보여주지 않습니다. / Earlier anatomy and pose reviews remain in the validation documents under `asset-staging/`; this viewer no longer shows the body.
