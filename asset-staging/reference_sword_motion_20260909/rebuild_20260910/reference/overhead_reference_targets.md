# Overhead reference: observed screen-space targets

Actual decoded source: `sU7jk2OQlgc.mp4`, 1280×720, 60fps. Frame ids are zero-based. Timestamp values are exact decoded presentation times; coordinates below are manual image observations with typical ±12px tolerance (±20px for clipped joints). No 3D values are recovered. Offscreen means no coordinate should be invented.

Read `overhead_reference_transfer.webp` (28,820 bytes) or the larger `overhead_reference_contact.webp` with the numbered rows below. Full resolution source PNGs and a machine-readable JSON are included.

Coordinates: x increases right, y increases down. Blade tilt is an image-plane angle from up, positive right. W = wrist joint center, G = blade-axis/crossguard intersection; neither is the grip center. R = highest visible shield rim point.

| # / frame / source time | W (x,y) | G (x,y) | Blade tilt | Tip (x,y) | R (x,y) |
|---|---|---|---|---|---|
| 01 / 1040 / 17.333333s | offscreen | (0.812, 0.847) | -6.6 | offscreen | (0.121, 0.785) |
| 02 / 1042 / 17.366667s | (0.987, 0.810) | (0.812, 0.625) | -15.0 | offscreen | (0.133, 0.812) |
| 03 / 1044 / 17.400000s | (0.992, 0.376) | (0.814, 0.303) | -16.7 | offscreen | (0.167, 0.861) |
| 04 / 1047 / 17.450000s | offscreen | offscreen | offscreen | offscreen | (0.219, 0.929) |
| 05 / 1074 / 17.900000s | offscreen | offscreen | offscreen | offscreen | offscreen |
| 06 / 1078 / 17.966667s | offscreen | offscreen | offscreen | offscreen | offscreen |
| 07 / 1080 / 18.000000s | (0.812, 0.264) | offscreen | offscreen | offscreen | offscreen |
| 08 / 1082 / 18.033333s | (0.635, 0.722) | (0.602, 0.464) | 8.1 | offscreen | offscreen |
| 09 / 1083 / 18.050000s | (0.551, 0.918) | (0.526, 0.671) | 9.0 | offscreen | offscreen |
| 10 / 1084 / 18.066667s | offscreen | (0.461, 0.869) | 12.5 | (0.549, 0.163) | offscreen |
| 11 / 1086 / 18.100000s | offscreen | offscreen | 11.9 | (0.487, 0.625) | offscreen |
| 12 / 1089 / 18.150000s | offscreen | offscreen | offscreen | offscreen | offscreen |
| 13 / 1110 / 18.500000s | offscreen | offscreen | offscreen | offscreen | (0.103, 0.824) |
| 14 / 1118 / 18.633333s | offscreen | (0.793, 0.974) | -24.1 | (0.630, 0.349) | (0.131, 0.767) |
| 15 / 1125 / 18.750000s | offscreen | (0.816, 0.783) | -6.3 | offscreen | (0.145, 0.801) |
| 16 / 1133 / 18.883333s | offscreen | (0.816, 0.825) | -3.1 | offscreen | (0.141, 0.785) |

## Non-negotiable visible silhouette checks

- 17.366667 and 17.400000: the forearm continues through the RIGHT boundary. The wrist is partly cropped at x≈0.99, not a complete arm hanging from the top of the frame.
- 18.000000: the wrist is around (0.813, 0.264), and its forearm remains continuously connected to the RIGHT boundary. The hand can leave the top; that does not mean the proximal arm/shoulder should enter from the top. No hollow cut face of an arm is exposed.
- 18.033333: wrist around (0.635, 0.722); forearm extends down-right and is cropped by the BOTTOM border around x≈0.66–0.83. 18.050000: wrist around (0.551, 0.918), arm extends through the BOTTOM border around x≈0.53–0.63. These two frames are the strongest checks against upside-down whole-arm rotation.
- In this 0.050000s visible strike interval (18.000000→18.050000), wrist travels rapidly from high-right to low-center. The right-arm silhouette must preserve a continuous connection toward the viewer body while the hand leads. Do not turn the entire visible arm as one rigid sword-linked object.
- Blade is almost edge-on through the downward pass: image tilt is only about +8° to +13° at 18.033333–18.100000. Broad blade faces during preparation/return are not a reason to keep a broad blade face during the cutting pass.
- Both weapons are absent at 17.900000/17.966667 and 18.150000. These are real source frames. Do not force wrist or sword to stay visible; do not use an offscreen phase to excuse a exposed arm cut face.
- Shield drops: highest rim y≈0.785 at 17.333333, 0.861 at17.400000,0.929 at17.450000, then offscreen during the cut. It reappears first at18.500000 (y≈0.824), before sword recovery at18.633333.
- Recovery blade tip is visible at18.633333 around(0.630,0.349), blade tilts left around−24°. It then rises into the upright, slightly left-leaning neutral silhouette by18.883333.

## Timing evidence and limits

- Preparation rises out of the frame between17.333333 and17.450000; 17.900000 and17.966667 are sampled offscreen hold poses.
- Main visible downward pass occurs18.000000–18.100000. Guard moves (0.602,0.464)→(0.526,0.671)→(0.461,0.869) at18.033333,18.050000,18.066667: each movement is only one source-frame interval (1/60s). This is much faster than the return.
- Source foreshortening/occlusion does not determine actual shoulder pivot, elbow world position, FOV, bone length or 3D Euler angles. Fit a connected rig to these image observations and verify rendered silhouettes; treat offscreen regions as unconstrained 3D, not zero coordinates.
