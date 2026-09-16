Source: https://github.com/Dari0us/Godot-Spatial-Fire-Raymarched
Commit: c5705d493b22afa1fa2dae26d60c9689f0af7279

MIT license retained. Torch integration uses the upstream noise/SDF/raymarch and color model, local-space proxy volume, adjusted sampling and smaller brightness. Campfire props not included.

Oil-soaked cloth revision: added an animated cylindrical surface-combustion zone spanning the measured cloth height, with an upward plume. The proxy uses explicit scene-depth ray termination so flames on the near side of opaque cloth are visible without drawing the far-side flames through it.
