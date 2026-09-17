# jump: reference screen targets

Actual decoded source at60fps,1280×720. Coordinates are manual2D observations, normalized x right/y down. Typical tolerance±20px; cropped/blurred landmarks are less certain. Null/offscreen is not a3D value. W=wrist joint, G=guard-axis junction, T=visible tip, R=topmost shield rim. Blade angle is image-plane only.

- Boundary includes f889=14.816667s lead-in, f890=14.833333s first selected lowering, through f980=16.333333s recovery plus f981=16.350000s continuity check. The video shows continuous motion; these are not hard animation cuts.
- Observed pose order: both equipment pieces sink (15.000000), rebound high (15.500000–15.666667), dip/foreshorten again (15.833333–16.000000), then settle (16.166667–16.350000).
- Shield top rim moves y≈0.817 at14.833333→0.928 at15.000000→0.647 at15.666667. Left-arm movement is a major visual cue; a shield remaining at y≈0.65 during takeoff would miss it.
- At15.000000 the sword guard and wrist are below frame. At15.500000–15.666667 the glove and some connected wrist appear lower-right. None of these poses show a detached shoulder entering from above.
- At16.000000 the sword tip is visible at(0.699,0.163), guard≈(0.763,0.942), blade leans left. The visible full blade and reduced projected length are essential to the landing response; expanding it toward upper-right produces the wrong silhouette.
- Takeoff/air/landing names describe visible inertia interpretation. Exact foot-ground contact time, trajectory height, gravity and3D pose cannot be measured from these first-person frames; game landing should remain grounded in actual collision.

| f / source seconds | W | G | blade angle | T | R |
|---|---|---|---|---|---|
| 889 / 14.816667 | offscreen | (0.812,0.885) | -4.1 | offscreen | (0.129,0.801) |
| 890 / 14.833333 | offscreen | (0.808,0.918) | -3.5 | offscreen | (0.136,0.825) |
| 900 / 15.000000 | offscreen | offscreen | -11.0 | offscreen | (0.199,0.928) |
| 910 / 15.166667 | offscreen | (0.793,0.917) | -20.0 | offscreen | (0.188,0.847) |
| 920 / 15.333333 | offscreen | (0.791,0.797) | -8.8 | offscreen | (0.153,0.747) |
| 930 / 15.500000 | (0.953,0.985) | (0.811,0.713) | -5.5 | offscreen | (0.102,0.667) |
| 940 / 15.666667 | (0.963,0.972) | (0.813,0.694) | -6.3 | offscreen | (0.087,0.647) |
| 950 / 15.833333 | offscreen | (0.785,0.944) | -7.5 | (0.709,0.024) | (0.108,0.850) |
| 960 / 16.000000 | offscreen | (0.763,0.942) | -7.6 | (0.699,0.163) | (0.105,0.744) |
| 970 / 16.166667 | offscreen | (0.786,0.903) | -4.2 | offscreen | (0.113,0.790) |
| 980 / 16.333333 | offscreen | (0.820,0.889) | -3.1 | offscreen | (0.121,0.819) |
| 981 / 16.350000 | offscreen | (0.818,0.875) | -3.3 | offscreen | (0.119,0.811) |

The contact-sheet cells are ordered left-to-right,top-to-bottom to match these rows. Exact original PNG filenames and all axis endpoints are in the JSON. Full PNGs remain local; the small transfer packet contains WebP+JSON+this document+extraction manifest only.
