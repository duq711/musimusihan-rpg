# Props and architecture review

The production factories and the test-room six-view gallery share the same geometry. Player body, arms and hands were excluded at the user's request. Chest hinge frames, arrow trajectories, flail anchors, effect timing, collision volumes and expedition state behavior remain authoritative.

## Completed visual iteration

- `equipment_iteration_01` and `props_iteration_02`: corrected chest lid end gaps and fastener placement, a faceted bow silhouette, wooden stave construction, cloth seams and vessel openings.
- `props_iteration_03`: reviewed actual bed, shelf, workbench, stool, sack, cloak, herbs, candles and saint together with production hideout scenes; added distinct support geometry, worn board edges, folds and leaves.
- `props_iteration_04`: reviewed 25 architecture, furniture and effect objects against generated references. Darkened pale stone, closed upper arch/column joins, seated chest fasteners and improved water glints.
- `final_iteration_01` and bounded correction rounds: reviewed all 51 owned objects. Corrected pale chest iron and trap stone, bright ember bars, yellow skull tint, faint drips, a box-shaped vice, below-ground camp flames, bright roast and sparse cooking surfaces. Further camp rounds corrected spotted broth, mushroom cap visibility and charcoal grain readability.
- `final_iteration_02`: directly reviewed all 51 again. The parent agent's combined-scene review then identified room junction gaps that isolated object views did not reveal.
- `hideout_junction_01` was rejected: a 94% backing closed the gaps but intersected weathered stone. `hideout_junction_02` verified 75% recessed cores and narrow opaque perimeter seals. Six missing central-hall arch headers and four original wall/ceiling gaps were filled with the same non-colliding wall family. Original passages and light placements remain.
- `hideout_hearth_01` replaced three rectangular bars with round coal-textured logs and rebuilt the nearby pot/cup with hollow walls, rims and curved handles. A low foundation and tangential ring blocks connect the stone hearth. Vertex-normal checks identified reversed vessel winding; `hideout_hearth_02` verified the correction in six views and four actual hideout cameras.
- `final_iteration_03`: directly reviewed the four changed objects against concepts, and compared decoded RGBA pixels for the other 47 objects. Of 282 directional images, 238 are identical and 44 differ. All 11 objects with differences were also visually rechecked; no additional geometry/material discrepancy was identified. The other 36 objects have exact six-view pixel identity with the directly reviewed final02 images.

The final comparison is qualitative. Per-object residual differences and verification methods are in `props_final_review.json` and `props_six_view_review_table.md`; exact cross-iteration image comparison is in `props_final_pixel_consistency.json`.

## Validation and capture evidence

Relevant architecture, chest, hideout, bow, flail, camp, cooking, skull, flame and material tests passed during their respective batches. Final retained local logs include:

- `godot-game/artifacts/visual_qa/dark_fantasy_join_regression_02.log`: three checks passed, including actual-mesh seam rays, stone/core nonpenetration, original collider bounds, unchanged doorways and actual central-hall hooks.
- `godot-game/artifacts/visual_qa/dark_fantasy_hearth_refinement.log`: three checks passed for the hearth composite and unchanged architecture/hideout behavior.
- `godot-game/artifacts/visual_qa/dark_fantasy_hearth_normals_02.log`: two checks passed after the winding correction, including outward exterior normals, inward cavity normals, upward inner floors, downward undersides and open-mouth/closed-bottom rays.

Final object manifest: `godot-game/artifacts/visual_qa/dark_fantasy_objects/final_iteration_03/capture_manifest.json`. All 126 objects and 756 Vulkan views completed through the embedded runner, with unchanged sources and preserved expedition/cursor state. An independent audit verified all 85 source hashes and all 756 directional image hashes. Manifest SHA-256: `a074c20fea680a051710c2d88c7d7151ba4ddb6afa7ac6cb7c1e73b7c1b95f12`.

Final combined scenes: `godot-game/artifacts/visual_qa/dark_fantasy_scenes/final_iteration_02/capture_manifest.json`. All ten scenes completed with 85 unchanged source hashes; all ten PNG hashes were independently verified. Camera positions, targets and field of view equal `baseline_torch_idle_04`. Scene manifest SHA-256: `760dded8f41168efbaa91731aa89009c7a69b94af48ddefd2fe28fdf0457449c`.

The final offline viewer is rebuilt from these completed captures. Headless Chrome verification with `--require-complete` passed: 126 concepts/baselines/current objects, 2,182 valid referenced files, ten matching scene-camera pairs, search, seven direction controls, keyboard navigation, modal controls and a 390px layout without horizontal overflow. All four saved desktop, scene, mobile and modal screenshots were directly inspected. The HTML SHA-256 is `32cbe27b4eedd2933718ea66c566b61e26d5e3197da4dbb15cddb69305e4dff8`; detailed results are recorded in `asset-staging/dark_fantasy_all_objects/review/viewer_qa.json`.

## Remaining differences

Generated concepts are aesthetic references rather than exact geometric projections. Several early top/bottom views were tilted or repeated perspectives. Some concepts invent adjoining stone frames, a different niche grid, thicker floor overlays, or alternate held/resting orientations. The game retains its playable dimensions and placements.

The saint has simpler folds and arm anatomy; curved arch stones retain overhead texture projection artifacts. Furniture wear and cooked ingredients are simpler than the concepts. The hearth's production platform is narrower than the generated composite, and its surfaces have less sculpted damage. Cooking steam uses repeated wisps; tiny drips remain small when framed as a complete falling field. No pixel-identity or numeric concept-similarity score is claimed. The gallery retains baseline lighting; production scene captures check torchlight, fog and ambient occlusion.
