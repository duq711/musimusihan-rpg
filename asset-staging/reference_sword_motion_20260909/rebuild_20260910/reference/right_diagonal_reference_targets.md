# right_diagonal: reference screen targets

Actual decoded source at60fps,1280×720. Coordinates are manual2D observations, normalized x right/y down. Typical tolerance±20px; cropped/blurred landmarks are less certain. Null/offscreen is not a3D value. W=wrist joint, G=guard-axis junction, T=visible tip, R=topmost shield rim. Blade angle is image-plane only.

- Boundary: lead-in f1269=21.150000s, rightward load f1270=21.166667s, final return f1365=22.750000s. Source asset boundary markers are not visible.
- Preparation exits the RIGHT edge. During21.866667→21.966667 the grip moves RIGHT→LEFT and down, while the blade points up-right. This differs from the left_reverse direction.
- Observed wrist x≈0.985→0.795→0.663→0.366 at21.866667,21.883333,21.900000,21.933333. Forearm extends down-right toward the viewer body, then crosses the bottom crop. Wrist and guard do not rotate as an unanchored rigid forearm.
- Tip moves from upper-right(0.840,0.419) at21.900000 toward center(0.494,0.469) at21.933333 then left(0.231,0.517) at21.966667. The hand lies BELOW the tip, crossing the lower half of the view.
- Shield is offscreen through the pass; it returns from low-left before the upright sword recovers. The faint blade at22.000000 has lower measurement confidence due motion blur.
- Null entries are offscreen or not reliably localizable. They are not zero-valued transforms.

| f / source seconds | W | G | blade angle | T | R |
|---|---|---|---|---|---|
| 1269 / 21.150000 | offscreen | (0.859,0.868) | -7.4 | offscreen | (0.130,0.799) |
| 1270 / 21.166667 | offscreen | (0.873,0.890) | -10.0 | offscreen | (0.134,0.801) |
| 1272 / 21.200000 | offscreen | offscreen | -15.0 | offscreen | (0.121,0.849) |
| 1311 / 21.850000 | offscreen | offscreen | offscreen | offscreen | offscreen |
| 1312 / 21.866667 | (0.985,0.787) | offscreen | offscreen | offscreen | offscreen |
| 1313 / 21.883333 | (0.795,0.783) | (0.797,0.617) | 63.4 | offscreen | offscreen |
| 1314 / 21.900000 | (0.663,0.833) | (0.653,0.650) | 55.4 | (0.840,0.419) | offscreen |
| 1316 / 21.933333 | (0.366,0.985) | (0.320,0.765) | 47.6 | (0.494,0.469) | offscreen |
| 1318 / 21.966667 | offscreen | (0.062,0.921) | 37.6 | (0.231,0.517) | offscreen |
| 1320 / 22.000000 | offscreen | offscreen | 11.6 | (0.036,0.626) | offscreen |
| 1351 / 22.516667 | offscreen | (0.789,0.954) | -20.1 | (0.654,0.282) | (0.129,0.771) |
| 1365 / 22.750000 | offscreen | (0.819,0.856) | -3.7 | offscreen | (0.138,0.812) |

The contact-sheet cells are ordered left-to-right,top-to-bottom to match these rows. Exact original PNG filenames and all axis endpoints are in the JSON. Full PNGs remain local; the small transfer packet contains WebP+JSON+this document+extraction manifest only.
