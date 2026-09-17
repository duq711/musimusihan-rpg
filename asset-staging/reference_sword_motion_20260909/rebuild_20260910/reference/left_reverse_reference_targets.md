# left_reverse: reference screen targets

Actual decoded source at60fps,1280×720. Coordinates are manual2D observations, normalized x right/y down. Typical tolerance±20px; cropped/blurred landmarks are less certain. Null/offscreen is not a3D value. W=wrist joint, G=guard-axis junction, T=visible tip, R=topmost shield rim. Blade angle is image-plane only.

- Boundary: sampled lead-in f1156=19.266667s, visible leftward load f1157=19.283333s; final return f1245=20.750000s. These are observation boundaries, not known source animation-asset start/end markers.
- Hand loads from lower-right toward left/down (19.283333→19.366667), then leaves the view. In the cutting pass19.883333→19.950000 it travels LEFT→RIGHT while the blade points left. Do not mirror it with the other cut.
- Wrist x progresses0.151→0.306→0.502→0.813 at19.883333,19.900000,19.916667,19.950000. The first three steps are consecutive60fps frames; this visible cross-screen pass is very fast.
- At19.900000 and19.916667 the forearm spans the lower screen and remains continuously attached toward bottom/right. The elbow-side body can remain cropped; no top-entry dangling shoulder/cut surface is visible.
- Shield is absent during the loaded hold and cutting pass, reappearing before the sword has fully recovered by20.533333. Retain this coordinated lowering rather than pinning the shield in neutral.
- Blade axis is broadly horizontal, about−86°/−82°/−78° from up during19.900000/19.916667/19.950000. These are screen angles only, not3D rotations.

| f / source seconds | W | G | blade angle | T | R |
|---|---|---|---|---|---|
| 1156 / 19.266667 | offscreen | (0.787,0.847) | -4.8 | offscreen | (0.137,0.801) |
| 1157 / 19.283333 | offscreen | (0.741,0.847) | -4.8 | offscreen | (0.125,0.819) |
| 1160 / 19.333333 | (0.590,0.994) | (0.480,0.831) | -15.1 | offscreen | (0.072,0.949) |
| 1162 / 19.366667 | (0.342,0.983) | (0.202,0.926) | -36.7 | offscreen | offscreen |
| 1191 / 19.850000 | offscreen | offscreen | offscreen | offscreen | offscreen |
| 1193 / 19.883333 | (0.151,0.850) | (0.007,0.782) | offscreen | offscreen | offscreen |
| 1194 / 19.900000 | (0.306,0.810) | (0.169,0.776) | -86.2 | offscreen | offscreen |
| 1195 / 19.916667 | (0.502,0.787) | (0.384,0.751) | -82.4 | offscreen | offscreen |
| 1197 / 19.950000 | (0.812,0.765) | (0.720,0.717) | -77.8 | (0.323,0.554) | offscreen |
| 1200 / 20.000000 | offscreen | offscreen | -73.9 | (0.707,0.554) | offscreen |
| 1232 / 20.533333 | offscreen | offscreen | -2.1 | (0.916,0.378) | (0.135,0.778) |
| 1245 / 20.750000 | offscreen | (0.822,0.847) | -3.3 | offscreen | (0.127,0.818) |

The contact-sheet cells are ordered left-to-right,top-to-bottom to match these rows. Exact original PNG filenames and all axis endpoints are in the JSON. Full PNGs remain local; the small transfer packet contains WebP+JSON+this document+extraction manifest only.
