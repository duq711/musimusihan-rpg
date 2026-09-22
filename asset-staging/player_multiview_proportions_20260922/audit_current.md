# Independent full-body candidate audit

Candidate GLB SHA-256: `3f4638ee9fe2e7f0925969eb63d4aba669316892ea21373f280f2a4d0b8e2af9`.

Read-only comparison against `player_reference_anatomy_20260922/Gravebound_Reference_Anatomy.blend`. All dimensions may change; preservation targets are identity, topology, texture layout and connected boundaries.

## Preservation and geometry

- All 20 mesh objects retain their topology, UV data, material names, world transforms and mesh metadata. Existing object metadata is retained; the revision tag is added.
- All 12 packed images remain byte-identical.
- No newly degenerate significant triangle or newly reversed significant triangle normal. Source-area threshold 1e-10 square metres excludes subprecision slivers. The torso has five microscopic opposed normals versus four before; none are significant-area triangles.
- Shoulder joins retain 229/228 source-coincident points, maximum separation .000240 mm. Both wrist joins retain 30 coincident points with zero separation.
- Pants are still tucked into separate boots. Pant lower Z.37238 remains below boot top .43541. Tracked nearest vertex-pair minima 3.73 mm left/3.62 mm right remain similar to source 3.86/3.37 mm; these are not visible gap measurements.

## Measured anchors

| Anchor | Actual Z | Reference guide Z |
|---|---:|---:|
| Crown | 1.719888 | 1.719888 |
| Belt AABB centre | .988163 | .984830 |
| Crotch bridge | .781622 | .781620 |
| Wrist shared-ring centre | .930478 | .930890 |
| Elbow section | 1.157930 | 1.157930 |
| Boot top | .435410 | .435410 |

The belt target is the remapped source centre. A nonlinear vertical map does not map an old AABB centre to the centre of the transformed AABB, explaining its3.33 mm difference. Wrist ring rotation similarly shifts the extrema midpoint by.41 mm.

## Wrist and forearm continuity

- Shared wrist centre abs(X)=.369494 m; its span is48.98 mm in world X,75.34 mm in depth and30.04 mm vertically. The ring is tilted and is smaller than the visible sleeve around it.
- The sleeve planar section atZ.93089 is57.99 mm wide, agreeing with the approximately60 mm reference wrist width. It grows smoothly to67.99 mm at.950,75.49 mm at.98483,78.34 mm at1.000 and88.35 mm at1.050.
- The hand section atZ.900 is59.05 mm wide. Shared seam vertices remain identical across the sleeve/hand split; the broad taper does not create a disconnected or elongated wrist connector.
- Regression limits distinguish the narrow joining ring from the surrounding cloth: shared X span45-70 mm, depth60-95 mm, vertical span below45 mm; the existing shared-vertex and wrist-height checks remain strict.

## Feet and crotch transition

- Low sole widths are129.31 mm atZ.025 and129.61 mm atZ.050. The earlier low-base pinch from fitting every foot height independently is absent from these sections.
- The ankle blends into a single scaled/yawed foot volume. Low foot centreX changes only.44 mm betweenZ.025 and.050, rather than the earlier18 mm shift. Actual front/side/top render review still determines appearance.
- Trouser half-widths across the upper-thigh/pelvis transition are205.64 mm atZ.750,206.98 mm at.78162 and208.28 mm at.800. The previous abrupt narrowing at the crotch-height slice is absent.

## Part bounds

| Part | Source X/Y/Z | Candidate X/Y/Z |
|---|---|---|
| Gravebound_AnatomicalHead | 0.1689/0.1992/0.2893 | 0.1731/0.1992/0.2905 |
| Gravebound_QuiltedTorso | 0.3965/0.2818/0.4944 | 0.3781/0.2757/0.5721 |
| Gravebound_FP_L_Hand | 0.0995/0.1243/0.2023 | 0.0844/0.1152/0.2017 |
| Gravebound_Trousers_L | 0.2151/0.2728/0.6915 | 0.2332/0.2676/0.6213 |
| Gravebound_Boot_L | 0.1820/0.3626/0.4578 | 0.1990/0.3117/0.4277 |
| Gravebound_Boot_R | 0.1822/0.3626/0.4578 | 0.1973/0.3117/0.4277 |

## Bilateral side-plane alignment

The final lower-limb field shifts Blender Y backward by 52 mm below height .28 m, 40 mm at .42 m, 20 mm at .52 m and zero by .85 m, using a smooth interpolation. The same field applies to trousers, boot shafts and cuffs; all their corresponding heights receive the same shift. The torso, head, eyes and hands do not use this field.

Actual boot-rim anterior maximum Y is .018921 m versus .056506 m before this final offset, a 37.585 mm shift at the .435410 m rim height. Wrist and fingertip coordinates are unchanged from the prior upper-body candidate. Pants/boot overlapping geometry remains in place, and the final audit still finds no significant newly inverted or degenerate triangles. Boot total front-back extent is .31166 m; planar foot widths and sole heights remain unchanged.

## Limits

The checks cover preservation, significant local degeneracy/winding, matching boundaries and selected cross sections. They do not certify no global self-intersection or exact anatomical/reference-view agreement. Actual rendered front/back/side review remains necessary.
