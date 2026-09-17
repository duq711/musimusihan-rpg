# Realistic open skeleton assets for a commercial Godot game

Research and local verification date: 2026-08-30 (Asia/Seoul).

## Recommendation

For a commercial or closed-source game, use the locally converted **official
BodyParts3D CC BY 4.0 GLB**:

`bodyparts3d_cc_by_sa/bodyparts3d_skeleton_cc_by_4_baked.glb`

It is heavier than the Z-Anatomy-derived GLB, but it has the cleanest verified
commercial license and avoids Z-Anatomy's ShareAlike scope dispute and its
separately credited noncommercial components. It was directly downloaded from
DBCLS's official archive, converted locally, imported by Godot 4.7, and rendered.

If compactness is more important and the game can satisfy CC BY-SA, the second
choice is:

`anatomi_simulatoru_z_anatomy/iskelet_without_ossicles.glb`

That conservative variant physically removes the six auditory-ossicle meshes
whose component provenance may overlap the noncommercial Dundee inner-ear model.

## Verified candidates

| Candidate | License and commercial status | Local result | Rig/animation | Verdict |
|---|---|---|---|---|
| BodyParts3D release 4.0, official DBCLS archive | **CC BY 4.0** since the official 2025-02-27 license update. Commercial use and adaptation allowed; attribution/change notice required; no ShareAlike. | Runtime-friendly baked GLB: 14,587,712 B, 202 meshes, 513,164 tris. Godot import/render passed. | No / no | **Best legal and provenance choice.** |
| Anatomi Simülatörü `iskelet.glb`, reproducibly exported from Z-Anatomy | **CC BY-SA 4.0** derivative. Commercial use allowed, but attribution and ShareAlike apply. The as-downloaded file contains six ossicle nodes with unresolved component-level provenance. | Original: 5,268,924 B, 277 nodes, 233 meshes, 320,179 tris. Conservative variant: 5,115,884 B, 271 nodes, 227 meshes, 310,287 tris. Both import; conservative variant rendered. | No / no | Best compact implementation only if BY-SA obligations and legal ambiguity are acceptable. Do not use the six ossicle meshes commercially without clearance. |
| NIH 3D 3DPX-016838 `Human Skeleton` | **CC BY 4.0**, commercial use allowed, direct NIH API download. | 9,593,028 B, one fused mesh, 532,878 tris, no normals/UV/material. | No / no | Legally permissive, but substantially worse for an articulated enemy. Requires separation, normal generation, rigging, and animation. |
| Direct BodyParts3D OBJ archive as downloaded | **CC BY 4.0**, same as first row. | 62 MB ZIP; extracted skeleton subset 33 MB / 202 OBJ meshes / 513,164 faces. | No / no | Trustworthy upstream source; converted GLB above is easier in Godot. |
| Anatomle overview skeleton | Site says **CC BY-SA 4.0**; provenance points to an unavailable AnatomyTool source. | 17 MB, 252 mesh instances, 508,782 tris, 135 materials and 132 embedded textures. | No / no | Visually good, but weaker provenance and larger than the selected options. |
| Sketchfab CC BY skeletons | Some pages state CC BY and downloadable, including one animated model. | No authenticated original archive/API token was available, so no original was obtained or validated. | Varies | Excluded: platform-authenticated download plus uncertain derivative provenance. |
| Smithsonian Human Origins models | Smithsonian pages restrict the relevant downloadable models to noncommercial use; full modern-human skeleton not obtained. | None | Varies | Excluded for a commercial game. |

## Direct sources and checksums

### BodyParts3D — recommended

- Official license: <https://dbarchive.biosciencedbc.jp/en/bodyparts3d/lic.html>
- Official archive page: <https://dbarchive.biosciencedbc.jp/en/bodyparts3d/data-8.html>
- Direct 99% OBJ ZIP: <https://dbarchive.biosciencedbc.jp/data/bodyparts3d/LATEST/partof_BP3D_4.0_obj_99.zip>
- Archive SHA-256: `9fbc713fffeee924a5a657d9813d84d7eb957bded63adb854931dd5e3eb61c97`
- Recommended baked GLB SHA-256: `3ff9ee03c42defe122027cba2887a9728924ca3764b52b3d91d46bd42ab33151`
- Required official credit: `BodyParts3D, © The Database Center for Life Science licensed under CC Attribution 4.0 International`.
- Conversion change notice: selected 202 skeleton element meshes, repackaged OBJ to GLB, and added a millimetre/Z-up to metre/Y-up root transform. No intentional topology or shape edit.

### Anatomi Simülatörü / Z-Anatomy — compact but ShareAlike

- Repository: <https://github.com/DrMuratAltun/anatomi-simulatoru>
- Direct GLB: <https://raw.githubusercontent.com/DrMuratAltun/anatomi-simulatoru/main/systems/iskelet.glb>
- GLB repository commit: `6a31f820ee15912871827a69db19a45bbea2a11b`
- Original GLB SHA-256: `43b4b27487db537e2e1ae2c87d3408f8d22943eb03eb6415a2833c865d82e4cf`
- Conservative GLB SHA-256: `c064affaf7d0f6363fad59ba88ae3b40c347aa815a6a66a1d1cec2b24b268f20`
- Immediate license/attribution files:
  <https://github.com/DrMuratAltun/anatomi-simulatoru/blob/main/LICENSE-DATA.md>,
  <https://github.com/DrMuratAltun/anatomi-simulatoru/blob/main/ATTRIBUTION.md>
- Upstream Z-Anatomy repository and attribution:
  <https://github.com/Z-Anatomy/Models-of-human-anatomy>
- Reproducible chain: the immediate repository downloads official
  `Z-Anatomy.zip`, opens `Startup.blend`, selects `1: Skeletal system`, applies
  decimation toward 320,000 triangles, and exports glTF through
  `tools/export_systems.py`.

### NIH 3D — permissive but fused/static

- Entry: <https://3d.nih.gov/entries/16838?version=2>
- Metadata API: <https://3d.nih.gov/api/entries/16838>
- Direct GLB API: <https://3d.nih.gov/api/files/498646>
- GLB SHA-256: `e29d217a59d71f954b871f5fa043548c43ff7904d684c55aa9a542b007d8dbb8`
- Creator shown by NIH: My Segmenter; source modality: CT; license: CC BY 4.0.

## Exact CC BY-SA scope for a Godot game

The controlling text is the CC BY-SA 4.0 legal code, not a shorthand sentence
in a repository README: <https://creativecommons.org/licenses/by-sa/4.0/legalcode.en>.

- Commercial sale is expressly allowed.
- When distributing the model or a modified model, retain supplied creator and
  copyright identification, the license notice/link, a practical source link,
  and a description of changes.
- Rigging, topology edits, decimation, baked pose changes, materials/textures,
  and animations embedded into the model can create Adapted Material. When that
  adapted model is shared, contributions to it must use CC BY-SA 4.0 (or an
  expressly compatible license).
- Mere technical format conversion does not by itself create Adapted Material
  under section 2(a)(4), though attribution is still required on redistribution.
- CC's official ShareAlike guidance says SA applies to adaptations, not mere
  collections/aggregations; placing an unmodified SA asset alongside unrelated
  material does not automatically relicense the unrelated material:
  <https://wiki.creativecommons.org/wiki/ShareAlike_interpretation>.
- Therefore, official CC guidance does **not** support a categorical claim that
  every line of Godot source code must automatically become CC BY-SA merely
  because a separable GLB is bundled. Classification can still depend on facts
  and jurisdiction. Z-Anatomy's maintainer has publicly asserted a broader
  interpretation that an app reading the model must release all code. A
  proprietary commercial developer should avoid that dispute by using the
  BodyParts3D CC BY 4.0 GLB.
- Do not add EULA terms or effective DRM that prevents recipients exercising
  the licensed rights in the CC asset. Keep the asset and its license notice
  separable, and carve the CC asset out of any proprietary EULA. CC's FAQ:
  <https://creativecommons.org/faq/#can-i-use-effective-technological-measures-such-as-drm-when-i-share-cc-licensed-material>.

This report is a technical license audit, not legal advice.
