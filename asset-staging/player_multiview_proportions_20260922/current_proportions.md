# Current full-body proportions

Source SHA-256: `0fc9c2d72db47cea5fb7cf48abe4db054955b41c9be9c99552938311072ee7f3`.

Read-only inspection of `Gravebound_Reference_Anatomy.blend`. No source or runtime change. Coordinates are metres; +Z up, +Y forward. Actual extrema/joins are distinguished from approximate joint guides. These are clothed static-mesh measurements, not a fitted skeleton.

## Landmarks

| Landmark | X | Y | Z | Basis |
|---|---:|---:|---:|---|
| crown | -0.00204 | 0.01272 | 1.71989 | mesh extrema |
| chin_approx | 0.00000 | 0.11500 | 1.51000 | visual/profile estimate |
| neckline_front | 0.07294 | 0.02570 | 1.46532 | local mesh extrema |
| neckline_back | -0.04486 | -0.05104 | 1.47773 | local mesh extrema |
| L_shoulder_section_center | -0.23347 | 0.00461 | 1.36000 | cross-section bbox center |
| L_elbow_section_center | -0.27757 | 0.00414 | 1.12920 | cross-section bbox center |
| L_distal_forearm_section_center | -0.32181 | 0.05779 | 0.94000 | cross-section bbox center |
| L_wrist_join | -0.32124 | 0.07538 | 0.88172 | shared sleeve/hand vertices |
| L_lowest_fingertip | -0.28781 | 0.10413 | 0.69362 | mesh extrema |
| L_knee_approx | 0.14205 | -0.02438 | 0.55000 | cross-section bbox center |
| L_thigh_section | 0.13213 | -0.01297 | 0.75000 | cross-section bbox center |
| L_ankle_section_approx | 0.14295 | 0.02107 | 0.15000 | cross-section bbox center |
| L_shin_section | 0.14310 | -0.00387 | 0.30000 | cross-section bbox center |
| L_boot_top | 0.14322 | 0.05651 | 0.46546 | mesh extrema |
| L_sole_bottom | 0.17519 | 0.24209 | 0.00767 | mesh extrema |
| L_toe_front | 0.17790 | 0.27073 | 0.04512 | mesh extrema |
| L_boot_cuff_top | 0.14322 | 0.06700 | 0.44628 | mesh extrema |
| R_shoulder_section_center | 0.23347 | 0.00461 | 1.36000 | cross-section bbox center |
| R_elbow_section_center | 0.27757 | 0.00414 | 1.12920 | cross-section bbox center |
| R_distal_forearm_section_center | 0.32181 | 0.05779 | 0.94000 | cross-section bbox center |
| R_wrist_join | 0.32124 | 0.07538 | 0.88172 | shared sleeve/hand vertices |
| R_lowest_fingertip | 0.28781 | 0.10413 | 0.69362 | mesh extrema |
| R_knee_approx | -0.13671 | -0.02438 | 0.55000 | cross-section bbox center |
| R_thigh_section | -0.13115 | -0.01292 | 0.75000 | cross-section bbox center |
| R_ankle_section_approx | -0.15563 | 0.02107 | 0.15000 | cross-section bbox center |
| R_shin_section | -0.15613 | -0.00387 | 0.30000 | cross-section bbox center |
| R_boot_top | -0.15601 | 0.05651 | 0.46546 | mesh extrema |
| R_sole_bottom | -0.18797 | 0.24209 | 0.00767 | mesh extrema |
| R_toe_front | -0.19069 | 0.27073 | 0.04512 | mesh extrema |
| R_boot_cuff_top | -0.15601 | 0.06700 | 0.44628 | mesh extrema |
| crotch_bridge_lowest | 0.00150 | -0.00150 | 0.81500 | central trousers geometry |
| belt_center | 0.00000 | 0.00000 | 1.08437 | belt bbox center |

Mesh suffix L/R does not use one consistent X-side convention across upper and lower limbs. Use the measured sign, not the name, when fitting legs against arms.

## Dimensions and ratios

- Overall height 1.7122 m. Crown Z1.7199, approximate chin Z1.510 gives 8.16 head units. Approximate crown-to-chin length .2099 m; the head object also contains neck geometry.
- Actual shared sleeve/hand join centres are X+/- .3212, Y.0754, Z.8817. Fingertip minimum Z.6936 lies 18.81 cm below the wrist join. Hand object height .2023 m includes glove/upper wrist.
- Shoulder section guide Z1.360; elbow guide Z1.1292; true shared wrist join Z.8817. Upper-arm guide segment length is approximately .235 m and forearm guide length approximately .261 m; true joint centres require a rig/body fit.
- Actual central trouser crotch bridge lowest Z.8150 is 47.6% of total height. Belt centre Z1.0844 is 63.3%. Clothing inseam and belt waist are separate landmarks.
- Original knee geometry is retained at Z.50-.62; .55 is used as a comparison guide. Boot cuff top Z.4463, boot mesh maximum Z.4655. The boot rim is not the anatomical knee.
- Each boot has front-back length 36.26 cm and width 18.2 cm. Boot length is 21.18% of total height and is a major visual proportion concern. Foot-length correction should be independent of preserving the shin/cuff connection.
- At shoe height Z.05, total left/right width is 52.34 cm; at thigh Z.75 it is 42.39 cm. Both exceed the chest-core width of 39.63 cm at Z1.30. This reflects stance plus shoe/leg width, not pure pelvis width.
- Boot axes are around X+.143 and -.156 m, about 6.5 mm off centre. This is a smaller issue than overall shoe length and stance.

## Contour by height

Core excludes arms, hands, pouches and belt. Whole-model contour includes them; widths near hand height are not torso width.

| Z | Whole width | Whole depth | Core width | Core depth |
|---:|---:|---:|---:|---:|
| 0.050 | 0.5234 | 0.3087 | 0.5234 | 0.3087 |
| 0.100 | 0.4457 | 0.2191 | 0.4457 | 0.2191 |
| 0.150 | 0.4113 | 0.1455 | 0.4113 | 0.1455 |
| 0.200 | 0.4052 | 0.1306 | 0.4052 | 0.1306 |
| 0.250 | 0.4059 | 0.1284 | 0.4059 | 0.1284 |
| 0.300 | 0.4116 | 0.1345 | 0.4116 | 0.1345 |
| 0.400 | 0.4383 | 0.1667 | 0.4383 | 0.1667 |
| 0.450 | 0.4303 | 0.1483 | 0.4303 | 0.1483 |
| 0.500 | 0.4163 | 0.1430 | 0.4163 | 0.1430 |
| 0.550 | 0.4247 | 0.1512 | 0.4247 | 0.1512 |
| 0.600 | 0.4183 | 0.1530 | 0.4183 | 0.1530 |
| 0.700 | 0.6241 | 0.2447 | 0.4179 | 0.1583 |
| 0.750 | 0.6720 | 0.2437 | 0.4239 | 0.1716 |
| 0.800 | 0.6970 | 0.2523 | 0.4202 | 0.1855 |
| 0.850 | 0.6970 | 0.2308 | 0.4085 | 0.2009 |
| 0.900 | 0.7442 | 0.2311 | 0.3907 | 0.2225 |
| 0.950 | 0.7395 | 0.2603 | 0.3636 | 0.2603 |
| 1.000 | 0.7246 | 0.3460 | 0.3606 | 0.2798 |
| 1.050 | 0.7073 | 0.3653 | 0.3340 | 0.2680 |
| 1.100 | 0.6830 | 0.3219 | 0.3255 | 0.2667 |
| 1.150 | 0.6586 | 0.2479 | 0.3348 | 0.2479 |
| 1.200 | 0.6386 | 0.2385 | 0.3521 | 0.2385 |
| 1.250 | 0.6171 | 0.2415 | 0.3779 | 0.2415 |
| 1.300 | 0.6020 | 0.2387 | 0.3963 | 0.2387 |
| 1.350 | 0.5612 | 0.2152 | 0.3918 | 0.2152 |
| 1.400 | 0.4846 | 0.1746 | 0.3793 | 0.1746 |
| 1.450 | 0.3033 | 0.1584 | 0.3033 | 0.1584 |
| 1.500 | 0.1155 | 0.1199 | 0.1155 | 0.1199 |
| 1.550 | 0.1228 | 0.1581 | 0.1228 | 0.1581 |
| 1.600 | 0.1683 | 0.1820 | 0.1683 | 0.1820 |
| 1.650 | 0.1419 | 0.1766 | 0.1419 | 0.1766 |
| 1.700 | 0.0967 | 0.1254 | 0.0967 | 0.1254 |

## Interpretation

Normalize total height before comparing reference silhouettes. Match head/neck/shoulder, chest/waist/pelvis, upper arm/forearm/hand, thigh/shin/foot together. Preserve identity, texture layout and connectivity while allowing scale changes to all body parts. The old hand/head sizes and previous AABB thresholds are not anatomical ground truth.

The supplied reference views should set the visual target. These measurements are a baseline, not anatomical standards. Boot length, stance, wrist lateral distance and chest width merit a coordinated full-body correction.
