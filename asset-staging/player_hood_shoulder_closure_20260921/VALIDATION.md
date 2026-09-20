# 후드 아래 어깨 틈 봉합 / Close shoulder gaps below the hood

이전 정수리 수정 뒤에도 후측상방에서 몸 안쪽이 보였다. 원인은 독립된 앞·뒤 망토 사이에 어깨 연결 천이 없는 것이었다. 실제 패널 상단 경계를 따라 양쪽 연결 천을 추가했다. 중앙은 6mm 완만한 아치, 가장자리는 8mm 겹침, 두께는 4mm다. 별도 알베도를 베이크하고 기존 MantleBack에 통합했다. 기존 28개 메시 구성을 유지하며 다른 27개 메시의 정점·면·UV·변환을 보존했다. 원래 후드와 앞·뒤 망토 패널도 보존한다.

English: The elevated rear/side view exposed missing shoulder cloth between the independent front and rear mantle panels. Add two continuous shoulder surfaces along their measured upper edges, with a gentle 6mm arch, 8mm overlap and 4mm thickness. Bake a separate fabric albedo and join the additions into MantleBack. Retain 28 mesh nodes and preserve the other 27 meshes plus the original hood and mantle panels.

- 원본 / Input: `../player_hood_redesign_20260921/Gravebound_Rebuilt_Hood.blend`.
- 제작 / Production: `geometry.py`, `build.py`, `Gravebound_Closed_Shoulder_Hood.blend`, `Gravebound_Shoulder_Cloth_Albedo.png`.
- 게임 결과 / Runtime: `../../godot-game/assets/3d/player/gravebound_player.glb`, byte-identical to `gravebound_player_closed_shoulder_hood.glb`.
- GLB SHA256: `0d90acc03ded051333e34c8ed077cb21710e355c143cd4600627b655b36d9431`.

## 검증 / Verification

- 새 연결 천 / New cloth: two sheets, each 1,197 vertices and 2,240 triangles before thickness. No zero-area or self-overlapping sheet triangles; upward-facing normals. Each thickened shell has no open or nonmanifold edges. Original source meshes preserved by signature comparison.
- 상단 광선 / Top coverage: 1,995 samples, 1,408 former gaps → 0 remaining gaps. `audit_coverage.py` checks the actual final joined mantle against the baseline.
- 후측·양옆 / Rear and sides: `audit_oblique.py` compares the same 1,679 surface samples from five elevated views. It blocks 351 previous torso/arm exposures. No quilted-torso exposure or newly exposed samples remain; remaining visible samples are the normal sleeve below the mantle hem. The intended face opening remains open.
- Godot: `player_fullbody_fp_arms` and `player_hood_closure` PASS. The same six vertical probes fail on the previous imported model and pass on the new imported model. Use projected barycentric coordinates to test the small cloth triangles precisely. `player_appearance` integration PASS.
- 실제 화면 / Actual rendering: 12 embedded Vulkan captures, including both elevated shoulders and the same view with neutral materials. Visually inspected by two reviewers: the former openings are filled with cloth; the dark seam is not a missing surface. Model SHA in the capture manifest matches the shipped GLB.
- 브라우저 / Browser: current localhost viewer reloads the new model; **어깨 연결** selects an elevated side view, with free orbit/zoom retained. Leave the current tab open for review.

렌더 / Renders: `../../godot-game/artifacts/visual_qa/player_appearance/closed_shoulder_20260921/`.

Mac Blender CLI와 기존 최소 Godot import / 통합 검사 환경으로 검증했다. Godot texture UID 경고는 경로로 정상 복구되며, 기존 ObjectDB 종료 경고 2개가 통합 로그에 남아 있다. 숨김 embedded 렌더는 데스크톱·포커스·소리를 사용하지 않고 원정·커서 상태를 보존했다. 기존 index 읽기 시간 초과 때문에 게시용 checkout에 이 작업 파일만 복사하여 공유한다.

English: Validate using Mac Blender CLI and the existing minimal Godot import/integration environments. Texture UID warnings recover through resource paths; the integration log retains two existing ObjectDB exit warnings. Embedded rendering preserves expedition/cursor state without a desktop window, focus changes or audio. Publish only this task's files from the existing publication checkout because the root index read times out.
