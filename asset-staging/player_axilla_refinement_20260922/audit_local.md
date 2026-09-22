# Local axilla refinement audit

Candidate GLB SHA-256: `e54f38efcba95a849eccbe958a6ab059a647de171101ab15cf851ee2ae61532c`.

Result: PASS.

Comparison is read-only against the approved full-body source. Only torso and two sleeve meshes may change. The broad guard is abs(X) .11-.29 m and Z 1.19-1.47 m; the detailed candidate mask is abs(X) .132-.234 m and Z 1.264-1.463 m. Only world Y depth may change; world X/Z silhouette coordinates must remain fixed. Guards are measured on original vertices. Position tolerance is .0005 mm for floating-point roundoff.

Packed images unchanged: True (12 images). Material graphs unchanged: True.

| Changed part | Vertices | Max displacement, mm | Outside guard |
|---|---:|---:|---:|
| Gravebound_FP_L_Arm | 8628 | 9.0742 | 0 |
| Gravebound_FP_R_Arm | 8646 | 9.2079 | 0 |
| Gravebound_QuiltedTorso | 10050 | 8.1039 | 0 |

## Shared boundaries

| Boundary | Points | Max gap, mm | Source normal angle max | Candidate normal angle max |
|---|---:|---:|---:|---:|
| L_shoulder | 229 | 0.000251 | 0.572079 | 0.530958 |
| L_wrist | 30 | 0.000000 | 53.129419 | 53.129419 |
| R_shoulder | 228 | 0.000244 | 0.383883 | 0.383883 |
| R_wrist | 30 | 0.000000 | 53.140821 | 53.142170 |

## Surface orientation

Normal rotation over 90 degrees is diagnostic, not automatically inverted winding. A deep saddle can change slope while retaining its exterior-facing direction. Check geometric normals against transported custom normals and preserved XZ-projection winding instead.

| Part | Newly opposed normals | Degenerate triangles | XZ winding reversals | Normals rotated over 90 degrees |
|---|---:|---:|---:|---:|
| Gravebound_FP_L_Arm | 0 | 0 | 0 | 0 |
| Gravebound_FP_R_Arm | 0 | 0 | 0 | 0 |
| Gravebound_QuiltedTorso | 0 | 0 | 0 | 0 |

## Scope and limits

Bounded preservation/continuity/local triangle audit. Does not certify global self-intersection absence or visual/anatomical acceptance.
