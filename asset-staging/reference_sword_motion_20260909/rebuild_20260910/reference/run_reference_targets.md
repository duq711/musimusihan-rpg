# run: reference screen targets

Actual decoded source at60fps,1280×720. Coordinates are manual2D observations, normalized x right/y down. Typical tolerance±20px; cropped/blurred landmarks are less certain. Null/offscreen is not a3D value. W=wrist joint, G=guard-axis junction, T=visible tip, R=topmost shield rim. Blade angle is image-plane only.

- Chosen complete faster-locomotion screen cycle: f707=11.783333s→f745=12.416667s, exactly38 source-frame intervals =0.633333s. Includes both endpoints; avoid duplicating the endpoint dwell when looping.
- Measurement: normalized template correlation of the crossguard patch over original frames420–840 found a38-frame recurrence in the faster11–14s section. The ten-frame position pattern f707..716 vs f745..754 differs by mean1.2243 original pixels. Contact-sheet visual inspection confirms near-identical sword/shield boundary silhouettes.
- Earlier7–9s locomotion repeats around58 frames=0.966667s. Do not use the earlier approximately1s estimate for this faster section. Input state and legs are absent, so this is a measured viewmodel cycle, not proven full-body stride or sprint-key state.
- Sword remains nearly upright throughout. Guard moves roughly x0.81–0.84,y0.82–0.91 in sampled frames. Blade tilt changes only a few degrees either side of vertical; no horizontal tucked-running pose.
- Two unequal vertical bobs occur inside the cycle: first low near11.90–11.95, rise by12.133333, second low near12.25–12.30, return by12.416667. Do not replace this shape with only one slow uniform sine.
- Shield stays cropped bottom-left and follows the stride with its own small roll/height change, upper rim around y0.75–0.83. Wrist joints mostly stay outside the lower crop; only fingers/glove are visible. The source floor gives real camera/world motion cues, absent from an empty-background turntable.

| f / source seconds | W | G | blade angle | T | R |
|---|---|---|---|---|---|
| 707 / 11.783333 | offscreen | (0.832,0.863) | -3.1 | offscreen | (0.176,0.754) |
| 710 / 11.833333 | offscreen | (0.834,0.876) | -3.6 | offscreen | (0.171,0.771) |
| 714 / 11.900000 | offscreen | (0.837,0.886) | -4.0 | offscreen | (0.166,0.817) |
| 717 / 11.950000 | offscreen | (0.838,0.890) | -3.9 | offscreen | (0.163,0.835) |
| 721 / 12.016667 | offscreen | (0.831,0.872) | -0.8 | offscreen | (0.148,0.814) |
| 724 / 12.066667 | offscreen | (0.812,0.851) | 0.9 | offscreen | (0.138,0.787) |
| 728 / 12.133333 | offscreen | (0.809,0.819) | 2.6 | offscreen | (0.113,0.774) |
| 731 / 12.183333 | offscreen | (0.821,0.838) | 3.1 | offscreen | (0.147,0.794) |
| 735 / 12.250000 | offscreen | (0.810,0.882) | 1.2 | offscreen | (0.129,0.804) |
| 738 / 12.300000 | offscreen | (0.813,0.911) | -0.7 | offscreen | (0.132,0.817) |
| 742 / 12.366667 | offscreen | (0.827,0.887) | -3.0 | offscreen | (0.160,0.769) |
| 745 / 12.416667 | offscreen | (0.832,0.863) | -3.1 | offscreen | (0.176,0.754) |

The contact-sheet cells are ordered left-to-right,top-to-bottom to match these rows. Exact original PNG filenames and all axis endpoints are in the JSON. Full PNGs remain local; the small transfer packet contains WebP+JSON+this document+extraction manifest only.
