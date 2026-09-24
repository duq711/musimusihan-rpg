# Roger + Medival 360° 뷰어 / Roger + Medival 360° viewer

로컬 파일 `godot-game/assets/licensed/roger/roger_medival.glb`가 있으면 Roger와 원본 Medival 의상을 함께 표시합니다. 이 파일이 없으면 `godot-game/assets/3d/player/medival_outfit.glb`의 원본 의상 5개(상의·벨트·바지·신발 2개)만 표시합니다. 이전 Gravebound 신체는 불러오지 않습니다. Roger 결합 파일은 로컬 라이선스 에셋이며 공개 저장소에 포함되지 않습니다.

English: If the local `godot-game/assets/licensed/roger/roger_medival.glb` exists, the viewer shows Roger wearing the original Medival outfit. Otherwise it shows only the five original clothing meshes from `godot-game/assets/3d/player/medival_outfit.glb`: shirt, belt, pants, and two shoes. It never loads the previous Gravebound body. The combined Roger file is a local licensed asset and is excluded from the public repository.

프로젝트 루트에서 실행 / Run from the project root:

```sh
python3 tools/player-model-viewer/server.py --port 8769
```

`http://127.0.0.1:8769/`에서 확인합니다. 서버는 localhost에만 연결하며 Ctrl+C로 종료합니다. 에셋을 수정하거나 로컬 Roger 파일을 추가했다면 새로고침하세요. `/roger-medival.glb`와 `/outfit.glb`는 정해진 파일만 제공합니다. 저장소 전체나 라이선스 폴더 전체를 웹 경로로 노출하지 않습니다.

English: Open `http://127.0.0.1:8769/`. The server binds to localhost only; stop it with Ctrl+C. Refresh after changing assets or adding the local Roger file. `/roger-medival.glb` and `/outfit.glb` serve only their designated files. The repository and licensed asset directory are not exposed as web roots.

- 왼쪽 드래그: 360° 회전 / Left drag: orbit.
- 휠: 확대·축소 / Wheel: zoom.
- 오른쪽 드래그 또는 Ctrl+왼쪽 드래그: 이동 / Right drag or Ctrl+left drag: pan.
- 전체·정면·후면·측면·머리·손 확대 / Whole model, front, back, side, head, and hands views.
- 의상만 보기: `Roger_`로 시작하는 신체 메시 숨김 / Outfit only: hide body meshes whose names start with `Roger_`.
- 형태 확인: 중립 재질로 형태 확인, 다시 누르면 원래 재질 복구 / Shape mode: inspect neutral shading, then restore the original materials.
- 자동 회전 / Auto-rotation.
- 터치: 한 손가락 회전, 두 손가락 확대·이동 / Touch: one-finger orbit, two-finger zoom and pan.

화면은 **피팅된 정적 미리보기**입니다. 실시간 천 물리나 옷의 움직임을 시뮬레이션하지 않습니다. Roger가 없거나 의상만 보기 상태에서는 머리·손 확대가 비활성화됩니다. 브라우저 조명은 Godot와 다를 수 있습니다. Three.js 0.170.0은 `vendor/`에 포함되어 있어 외부 CDN 요청이 없습니다.

English: This is a **fitted static preview**, with no real-time cloth or garment motion simulation. Head and hand controls are disabled when Roger is unavailable or hidden. Browser lighting can differ from Godot. Three.js 0.170.0 is vendored locally; no external CDN is used.

`/model-info.json`에서 선택된 파일의 이름·원본 경로·해시·크기 및 Roger/의상 파일 각각의 가용 여부를 확인할 수 있습니다. 브라우저의 `window.playerViewer`에는 실제 메시 이름, `bodyMeshNames`, `garmentMeshNames`, `missingGarmentNames`, 바운드와 보기 상태를 기록합니다. 의상 이름은 `Medival_ShirtUpper`, `Medival_Pants`, `Medival_Belt`, `Medival_Shoe_L`, `Medival_Shoe_R`입니다. 결합 GLB는 Y-up, 정면 -Z, 발 높이 0을 기준으로 합니다.

English: `/model-info.json` reports the selected file name, origin, hash, size, and separate Roger/outfit availability. `window.playerViewer` exposes actual mesh names, `bodyMeshNames`, `garmentMeshNames`, `missingGarmentNames`, bounds, and view state for review. Expected garment names are listed above. The combined GLB uses Y-up, faces -Z, and places the feet at height zero.

이전 의상 제작 자료는 `asset-staging/medival_cloth_20260923/`와 `asset-staging/medival_clean_20260924/`에 보존되어 있습니다. / Earlier garment production files are preserved in those staging folders.
