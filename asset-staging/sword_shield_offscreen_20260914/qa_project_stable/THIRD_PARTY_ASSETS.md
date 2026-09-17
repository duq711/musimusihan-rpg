# Third-party assets

## BodyParts3D anatomical skeleton

- Runtime file: `assets/3d/dark_fantasy/anatomical_skeleton_cc_by_4.glb`
- Source dataset: BodyParts3D release 4.0, 99% polygon mesh archive
- Official archive: <https://dbarchive.biosciencedbc.jp/data/bodyparts3d/LATEST/partof_BP3D_4.0_obj_99.zip>
- Dataset record and DOI: <https://dbarchive.biosciencedbc.jp/en/bodyparts3d/data-8.html>, <https://doi.org/10.18908/lsdba.nbdc00837-008>
- Official license page: <https://dbarchive.biosciencedbc.jp/en/bodyparts3d/lic.html>
- License: Creative Commons Attribution 4.0 International, <https://creativecommons.org/licenses/by/4.0/>
- Source ZIP SHA-256: `9fbc713fffeee924a5a657d9813d84d7eb957bded63adb854931dd5e3eb61c97`
- Runtime GLB SHA-256: `3ff9ee03c42defe122027cba2887a9728924ca3764b52b3d91d46bd42ab33151`

Required attribution:

> BodyParts3D, © The Database Center for Life Science licensed under CC Attribution 4.0 International.

Local changes: selected the 202 source elements that collectively render the complete skeleton; repackaged their OBJ geometry as binary glTF; baked the source millimetre/Z-up coordinates to metre/Y-up coordinates; preserved each official `FJ…` element ID as its mesh-node name; added a Godot-only rigid joint hierarchy, pose animation, scale/orientation alignment, and a weathered-bone material override. No source topology or anatomical shape was intentionally changed.

The user-supplied stock photograph is used only as a visual reference for proportion, surface colour, and pose. Its pixels, white background, and watermark are not embedded in the game or model.
