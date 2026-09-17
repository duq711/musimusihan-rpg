# Sword/shield reference motion analysis

Source: https://youtu.be/sU7jk2OQlgc . Local `sU7jk2OQlgc.mp4`, 1280 × 720, 60 fps, 53.533 s video stream. These observations use sequential PyAV decoding of the actual downloaded video, not browser screenshots. Contact-sheet labels are desired sample times; the selected decoded frame is within one source frame. Screen coordinates below are approximate visual measurements, origin top left, x/W and y/H. They are **screen-space direction**, not recovered world transforms.

## Read first

- This is a first-person right-hand sword / left-hand round shield showcase. Only arms are visible. There is no grounded evidence of the source character's full-body leg gait, exact camera FOV, rig lengths, or input state.
- The strong matching cues are the upright neutral silhouette, restrained locomotion sway, two-stage jump inertia, large shoulder/elbow attack arcs, long preparation, a very fast cutting pass, and slower recovery.
- The video contains **three distinct cutting directions plus a thrust**, followed by two combination examples. Do not label the thrust as one of the three cuts.
- Many decoded attack frames show the environment and NO weapons at all. This is actually in the source video. Weapons leave the visible frame during preparation and follow-through. It is not a failed browser seek. Match those broad offscreen arcs if desired, but maintain a continuous rig and geometry rather than hiding meshes.

## Neutral pose and locomotion

Best inspection: `locomotion_06_14_*.jpg` and `run_dense_*.jpg`.

- Around 5.0–14.7 s, the sword occupies the right side. Crossguard center is roughly (0.79, 0.87), glove around (0.81, 0.97). Blade extends beyond the top edge, with about 0–6° left lean in the image. This near-vertical long sword is the defining silhouette; there is no horizontal tucked sprint posture in the visible locomotion section.
- Shield is low left, its upper rim around y = 0.79–0.85, occupying x = 0–0.38. Its center stays below the lower image edge. No static shield float at center screen.
- During movement the sword stays approximately x = 0.77–0.83, with small alternating wrist lean and a rounded rise/fall. Crossguard movement is around 0.04–0.08 H peak-to-peak, and horizontal hand travel around 0.03–0.05 W. These are approximate image readings, not fitted calibration values.
- At 8.00 s the sword guard is up; 8.25–8.45 s it is lower; 8.55–8.65 s it rises; 8.75–8.90 s it drops again; 9.15–9.35 s it rises. A practical initial loop is roughly 0.9–1.1 s per left/right cycle with two footfall bobs, then tune against the rendered result. Do not claim this is a measured exact animation clip period.
- Shield and sword share broad body vertical movement but differ slightly in pitch/roll and timing. Hands retain a firm grip; movement comes from shoulders, elbows, and wrist alignment, not sliding the sword within the glove.
- The checker-floor movement establishes locomotion. The recording does not show walk/sprint labels or input, so an exact walk/run state boundary cannot be inferred confidently.

## Jump, takeoff and landing

Best inspection: `jump_14_17_01.jpg`. A single jump response is visible approximately 14.83–16.33 s.

| Source time | Visible direction |
|---|---|
| 14.667 | Ordinary upright locomotion pose. |
| 14.833–15.000 | Takeoff inertia: both hands/shield drop. At 15.000 the sword guard is below the frame; sword leans farther left than neutral and shield is almost fully below the frame. |
| 15.167 | Arms begin rebounding; sword remains leaned left (~12–15°), guard returning from the lower edge. |
| 15.333–15.667 | Airborne rebound: sword hand rises noticeably, with more right forearm visible. At 15.500–15.667 guard is around y = 0.73–0.77, well above neutral; shield rim also rises to around y = 0.68–0.72. |
| 15.833–16.000 | Landing compression: blade pitches forward/down, entire sword becomes shorter in projection, tip is now visible. At 16.000 tip is around (0.69, 0.16), guard near (0.78, 0.95); both hands are low again. |
| 16.167–16.333 | Damped recovery to neutral upright guard. |

Implementation direction: separate takeoff impulse, airborne pose and ground-contact recovery so long falls do not prematurely play the landing. Use the actual game ground contact to trigger the second dip. Preserve the above pose order even if gameplay jump duration differs.

## Cut 1: overhead downward

Best inspection: `overhead_dense_01.jpg`, `attack_17_21_01.jpg`.

- Neutral through 17.30. Preparation starts ~17.33.
- 17.40: right hand rises sharply to high right, grip roughly (0.87, 0.42), blade continuing above the image; shield drops.
- 17.45–17.95: sword raised out of frame while holding preparation.
- 18.00: hand/forearm reenter from upper right. The right arm reaches high forward, with grip around (0.72, 0.11).
- 18.05: blade is edge-on/nearly vertical through the central-right screen, grip now roughly (0.55, 0.75); this is the very fast descending pass.
- 18.10: blade finishes down near center (tip around x = 0.49, y = 0.63); hand below image. By 18.15 it has fully left the lower frame.
- 18.45–18.65: shield reappears first, then blade comes back from low right, pointing diagonally up-left.
- 18.75–18.88: settles to upright neutral.
- Timing starting point: 0.12 s lift + 0.50 s held anticipation + 0.15 s cut + 0.30 s low follow-through + 0.45 s return = about 1.5 s total. Avoid a uniform-speed rotation.

## Cut 2: left-to-right horizontal backhand

Best inspection: `left_right_dense_01.jpg`, `attack_17_21_02.jpg`.

- Starts ~19.28. At 19.35 sword hand travels to lower center-left while blade leans up-left. At 19.375 the glove is near the left edge. This crosses the right arm in front of the body to load the opposite side.
- 19.40–19.85: loaded beyond left/down frame edge; shield is also lowered out of view.
- 19.90: arm sweeps into view from left; forearm stretches horizontally across the lower screen. Grip around (0.25, 0.82), blade pointing left out of frame.
- 19.95: rightward sweep reaches grip around (0.72, 0.78); blade remains broadly horizontal, tip to left near horizon.
- 20.00: only blade sliver remains at far right as the pass completes. By 20.05 both weapons are absent.
- 20.375: shield reappears; 20.50 sword tip rises from the lower right; 20.625–20.75 return to neutral.
- About 0.12 s load + 0.48 s hold + 0.15 s pass + 0.25–0.30 s overshoot + 0.4 s return; total ~1.45 s.

## Cut 3: right-to-left diagonal forehand

Best inspection: `right_left_dense_01.jpg`, `attack_21_25_01.jpg`.

- Starts ~21.16. At 21.20 sword moves rapidly to far right; hand/blade load beyond right edge by 21.25.
- 21.25–21.85: right-side preparation offscreen.
- 21.875: grip first enters far right, with pommel directed left/down and blade to upper right.
- 21.90: grip around (0.60, 0.81), blade slopes up-right toward (0.85, 0.54).
- 21.95: grip has crossed to lower left, blade still pointing diagonally up-right. The forearm/wrist passes across the lower center; follow-through continues down-left.
- 22.00: only blade at left/lower edge; 22.05 onward below/offscreen.
- 22.375 shield returns; 22.50 sword rises diagonally from low right; 22.625–22.75 neutral.
- This is not the same direction as Cut 2 played again. The screen-space grip path travels right → left, whereas Cut 2 travels left → right. Preserve distinct shoulder and wrist rolls.

## Additional source behavior

- Thrust, ~23.12–25.00: sword lowers from neutral through low right (23.15–23.25), remains withdrawn offscreen until ~24.10, then projects forward with tip close to reticle/horizon around (0.50, 0.55) at 24.20–24.35. Hand is roughly (0.63, 0.94) with right forearm stretched from screen edge. Retracts and rises to neutral by 25.00. See `thrust_dense_*.jpg` and `attack_21_25_02.jpg`.
- Combination example ~26.18–29.25 contains overhead pass around 26.70, left/right broad pass around 27.25, opposite pass around 27.75, another lateral pass around 28.375, then returns. It demonstrates chaining without a complete neutral settle after each stroke; do not create a compulsory idle between cuts.
- Second combination ~29.68–32.25 shows an overhead/raised pass around 30.00 and a thrust extension around 31.375–31.625.
- Guard ~33.45–48.8: shield rises to cover the lower center with rim near y = 0.56–0.65, sword lowers to the right with only diagonal blade visible, tip around (0.78, 0.56). Shield remains a physical left-arm motion. Around 35 s a jump/bob occurs while guarding, preserving raised shield pose. See `guard_33_35_01.jpg`.

## Suggested acceptance checks against the reference

1. Neutral weapon placement and blade lean match before checking animation curves.
2. Locomotion keeps sword upright with restrained two-footfall bob, coherent shield motion and planted glove grip.
3. Jump clearly reads low → high → landing low → settle, with landing controlled by gameplay contact.
4. Cuts have visibly distinct overhead, left→right, right→left screen paths, a fast ~0.15 s cutting pass and a slower return.
5. Shield drops during wide attacks and returns before/with sword; no wrist break, detached glove, or shield moving independently of the left arm.
6. Compare rendered Windows-produced key poses at the timestamps above. The 2D source alone cannot prove recovered 3D rig accuracy or exact motion capture equivalence.
