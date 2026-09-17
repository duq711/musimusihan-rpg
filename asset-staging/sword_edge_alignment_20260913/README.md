# Forehand blade alignment — 2026-09-13

The user's new reference requires laying the blade with the wrist before the right-to-left cut. The preceding instruction to avoid an extra upward preparation remains in force. The reference screenshot is supported by directly inspected local video frames at 21.90–21.97s; these are observations, not recovered motion capture.

`baseline/` preserves the previous direct-entry implementation and original delivered motion. `author_edge_cut.py` runs in background Mac Blender 5.2.1 and writes `candidate_01/Forehand_Edge_Aligned.blend`, editable controls, and the new motion manifest. Only the `right_diagonal` sword track and dependent right-arm samples change. Other clips, shield samples, timestamps, combat timing and original model files remain preserved (`source_preservation.json`).

The broad blade face is XY and its normal is Z in the actual normalized sword mesh. The cut uses a shallow upper-right length axis and a fixed blade plane. The hand path is projected into that plane, so the blade edge leads its transverse movement. The blade continues toward the upper right relative to the grip while the hand travels left/down; it no longer flips its length direction after contact. Recovery joins the existing upright idle.

The real player rotates around the captured grip during the existing WINDUP for 0.14s. It then connects the laid pose to the authored cut during ACTIVE's first 0.10s. A redundant whole-pose handoff was removed for this wrist turn after the first regression run exposed 3.707mm of grip drift. The separate handoff is retained for other cuts and shield motion. The first regression run also exposed a test input scheduling error: its added 0.14s checkpoint shifted a 0.45s release to a later frame. The fixture now splits at the exact requested release time; gameplay clocks were not changed.

`preflight.log` checks motion loading/playback, capture configuration and actual attack transactions. `edge_alignment.log` checks the actual source mesh and 255 samples of blade movement through the production sampler. `regressions.log` is the superseded first run; `final_regressions.log` records the corrected implementation. Earlier `edge_aligned_*` captures precede the grip handoff correction. Only `edge_aligned_final_*` captures and comparison should be used for the final result.

This change addresses forehand orientation and trajectory. It does not claim to reconstruct reference mocap or repair the previously rejected thumb/left-hand mesh refinements. Original hand assets are kept.
