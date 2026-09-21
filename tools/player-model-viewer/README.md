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
- 머리 확대: 후드를 제거한 머리와 얼굴을 가까이 봅니다. / Head focus: inspect the exposed head and face.
- 어깨 연결: 후드 천을 제거한 목과 소매 연결을 높은 사선에서 살펴봅니다. / Shoulder join: inspect the exposed neck and sleeve joins from above.
- 터치: 한 손가락 회전, 두 손가락 확대·이동 / Touch: one finger orbit, two fingers zoom/pan.

Three.js 0.170.0의 필요한 파일만 vendor에 고정 포함했습니다(MIT, vendor/LICENSE). 런타임 외부 CDN 요청은 없습니다.

English: Required Three.js 0.170.0 files are vendored under MIT (vendor/LICENSE), with no external CDN requests at runtime.

검증 / Validation: Codex 실제 브라우저에서 모델 로드, 드래그 회전, 휠 확대·축소, 손 확대 및 전신 맞춤을 확인했습니다. 사용자가 제공한 머리·눈 모델로 교체하는 최신 작업의 검증 상태는 [제공 모델 검증 기록](../../asset-staging/player_supplied_face_20260921/VALIDATION.md)에 기록합니다. 범용 라이브러리의 오른쪽 드래그 이동 경로는 코드에서 확인했습니다.

English: Verified loading, drag orbit, wheel zoom, hand focus and full-body reset in the live Codex browser. Current supplied-head replacement status is recorded in the [validation document](../../asset-staging/player_supplied_face_20260921/VALIDATION.md). Right-drag pan uses the library's standard controls and was checked in code.

최신 의상 변경 / Latest outfit change: [목·어깨 후드 제거 검증](../../asset-staging/player_cowl_removed_20260922/VALIDATION.md).

목·어깨 연결 재구성 / Rebuilt neck and shoulder joins: [구조·화면 검증](../../asset-staging/player_natural_shoulders_20260922/VALIDATION.md).

- 상체 비율: 목·어깨·가슴을 사선 정면에서 확인합니다. / Upper-body view: inspect neck, shoulders and chest from the front oblique.
- 형태 확인: 색상과 무늬를 잠시 끄고 무채색으로 형태를 봅니다. 다시 누르면 원래 재질로 돌아옵니다. 게임 에셋은 변경하지 않습니다. / Shape inspection toggles neutral clay shading and restores the original materials, without modifying the game asset.

코트 자락 제거 및 바지 완성 / Coat-tail removal and completed trousers: [하의 검증 기록](../../asset-staging/player_trousers_only_20260922/VALIDATION.md). 전신 맞춤으로 변경된 복장을 확인합니다. Use Fit body to inspect the updated outfit.

가슴·등·어깨·위팔 형태 수정 / Resculpted chest-to-arm transitions: [형태 검증 기록](../../asset-staging/player_shoulder_form_20260922/VALIDATION.md). 상체 비율과 형태 확인 버튼으로 검토합니다. Use Upper-body view and Shape inspection for review.

2026-09-22 복원 / Restoration: 사용자 요청으로 마지막 어깨 조형을 철회하고 `f279eec` 모델로 복귀했습니다. 현재 게임 GLB SHA256: `f7ad57eddd4ac751daee53fcdb05bf627a749007f0989d9f344f735dfb2e2a77`. The viewer serves the restored previous model, preserving the face, hands and trousers. Evidence: [복원 기록](../../asset-staging/player_shoulder_rollback_20260922/VALIDATION.md).
