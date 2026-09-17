# Windows first-person sword motion, iteration 02

Status: NONCANONICAL_PREVIEW. Windows authoring, Blender/GLB readback and preview rendering are complete. Godot integration and reference-video similarity have not been verified here.

## Files and clips

- Reference_Sword_Motion.blend: authored scene with eight layered Actions.
- Reference_Sword_Motion.glb: eight animations; each animates sword and shield position/rotation.
- motion_samples_120hz.json: full-precision camera-space samples and separately recorded source pivots/video idle controls.
- FirstPerson_8Clips_Preview.mp4: 8.1-second, 768 x 432, 30 fps rendered preview.
- verification/motion_verification.json: independent readback results.
- FirstPerson_8Clips_Preview.json: encoding, decode and hash results.

The clips are idle (1 s, loop), run (1 s, loop), takeoff (0.30 s), air (0.80 s, loop), land (0.40 s), right_diagonal (1.59 s), left_reverse (1.47 s) and overhead (1.55 s). Both Sword_Control and Shield_Control are present in each Action.

Use author_motion.activate_action(name, seconds) after loading the blend to activate both slots. The scene custom property motion_action_control_map records slot identifiers. NLA tracks are muted for preview, with idle assigned actively; this is intentional. The fixed camera uses a 76-degree field of view and 16:9 aspect ratio.

## Verification completed

Independent Blender reopening and fresh GLB import passed. Eight clips, two animated controls per clip and all eleven original right-hand/sword mesh vertex hashes were checked. The maximum sampled world-matrix difference after GLB import was 2.980232238769531e-7. The original input files were unchanged.

The idle, run and air loop endpoints match. The sampled linear-velocity seam difference is zero; the maximum sampled angular-velocity difference is approximately 3.686e-6 rad/s. These are one-sided finite differences of the baked 120 Hz samples, not an analytic continuity proof.

The preview rendered on the Windows RTX 4090 with Cycles OptiX. All 243 encoded video frames were decoded successfully. The historical authoring_report.json was written before independent verification and still contains its earlier pending field; the later verification and preview reports supersede that field.

## Visual and integration limits

The long handle and source hand grip geometry are preserved. Fingers do not deform during these motions: the entire existing grip/forearm moves under rigid controls. The standalone scene does not include the game's shoulder/arm connector. Large attack rotations can reveal the cut sleeve end; this requires checking with the game's existing connector before acceptance. The left hand comes from the older game reference and has a fingerless glove, while the right hand has a full glove.

Motion timing follows the reference-video observations supplied by the coordinating task. Windows did not receive or directly inspect the reference video/contact sheets. Movement amplitudes are authored estimates; no frame-by-frame similarity claim is made.

The local motion_manifest.json is a draft and is not validated against the receiving Mac schema. Receiving canonical ready transforms and explicit hit instants remain necessary for final conversion. Video idle is different from source ready. Camera-space conversion is M_raw(t) * inverse(T_source_pivot) * M_receiving_canonical_ready; changing quaternion component order alone is insufficient. The prepared converter and exact received schema are in ../../contracts.

## Thread transfer

The immutable first transfer ZIP is ../../thread_transfer/reference_sword_manifest_v1.zip (105867 bytes, 12 base64 chunks). SHA256: 390fb2509eea7f4db112f0043c16871d6b3e8ff694b03026daa9d33a24ee2f42. It contains exact time/position/quaternion values, source pivots, scripts and reports, with redundant derived matrices omitted. Use Python zipfile for its LZMA compression. Chunk emission is complete; receipt by the Mac has not yet been confirmed.
