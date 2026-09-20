# 후드 정수리 재설계 / Hood crown redesign

사용자가 360° 뷰어에서 발견한 정수리 구멍과 방사형 갈라짐을 수정했다. 닫힌 둥근 정수리, 뒤통수로 이어지는 곡면, 4mm 천 두께와 어두운 안감을 새로 제작했다. 얼굴 개구부를 유지하고 이마 위 두피가 천과 안감을 관통하지 않도록 여유를 확보했다. 기존 의상 컨셉의 천 영역을 새 UV 알베도로 베이크했다.

English: Rebuild the hood with a closed rounded crown, continuous back, 4mm cloth thickness and dark lining. Preserve the face opening and provide scalp clearance beneath the brow. Bake a new UV albedo from the existing outfit concept fabric.

- 제작 / Source: `Gravebound_Rebuilt_Hood.blend`, `build.py`, `Gravebound_Rebuilt_Hood_Albedo.png`.
- 게임 결과 / Runtime output: `../../godot-game/assets/3d/player/gravebound_player.glb` (same bytes as `gravebound_player_rebuilt_hood.glb`).
- SHA256: `1ab9dbe1b5584e8063b2c65eb65ed84198f0f9edf52d1f4a1721effd78985ac6`.
- 이전 원본 / Preserved input: `../player_inward_palms_20260921/Gravebound_Inward_Palms.blend`.
- 범위 / Scope: `Gravebound_PointHood`만 교체. 다른 27개 메시의 정점·면·UV·변환 비교 일치. / Only the hood changes; vertex, face, UV and transform signatures match for all 27 other meshes.

## 검증 / Validation

- 메시 / Mesh: 11,618 vertices, 23,232 triangles, 1 connected shell. Open boundaries, nonmanifold edges, zero-area faces and confirmed self-intersections: 0.
- 정수리 / Crown: 864/864 independent downward rays hit a continuous upward-facing surface. The builder also checks 441 crown rays.
- 이마 / Brow: 932 valid shell-and-scalp samples, no sampled intersections. Minimum outer clearance 4.934mm; lining clearance 1.428mm. Rays through the intended face aperture or outside the scalp are excluded explicitly.
- Godot: `player_fullbody_fp_arms` PASS; `player_appearance` PASS (shared body/portrait, camera layers, inventory rotation, test-room/dungeon transitions and state restoration).
- 실제 렌더 / Actual rendering: embedded Vulkan runner, 9 captures including crown, high angle, rear and isolated untextured crown. Manifest model SHA matches the final GLB. No native game window, desktop capture, audio or focus changes; expedition and cursor state preserved.
- 브라우저 / Browser: final game GLB loaded in the current 360° viewer; hood focus and crown buttons visually verified. The crown is closed and the previous brow protrusion is absent. Free orbit/zoom remains available.

실제 렌더 / Render evidence: `../../godot-game/artifacts/visual_qa/player_appearance/rebuilt_hood_20260921_final/`.

검증은 Mac Blender CLI, 최소 Godot import 프로젝트 및 기존 통합 검사 사본에서 실행했다. Godot 격리 캐시의 texture UID fallback 경고와 기존 종료 시 ObjectDB 2개 경고가 로그에 남아 있으나 검사와 렌더는 통과했다. 정적 전신 에셋 검사이며 새로운 후드 애니메이션 검증을 의미하지 않는다.

English: Run with Mac Blender CLI, a minimal Godot import project and the existing integration snapshot. Logs retain texture UID path-fallback warnings from the isolated cache and two existing ObjectDB exit warnings; tests and rendering pass. This validates the static full-body asset, not new hood animation.

루트 저장소의 기존 index 읽기 시간 초과를 피해 기존 게시용 checkout에 이 작업 파일만 복사하여 게시한다. 원본 index와 다른 진행 중 파일은 수정하지 않는다.

English: Publish only this task's files through the existing publication checkout because the root index read times out. Preserve that index and unrelated work.
