# Geology sampling investigation (not applied)

Godot provides textureGrad with explicit coordinate gradients. GLSL documents implicit derivatives as undefined in non-uniform control flow. Thus pixel-varying axis branches must use gradients evaluated before those branches; simply wrapping the current texture() calls in if(weight > 0) is unsafe.

A possible exact-weight implementation:
- Compute dFdx(p), dFdy(p) in converged fragment flow before any axis branches.
- Pass the same swizzled gradients as each projection: p.zy, p.xz, p.xy.
- Multiply both gradients by the same uniform coordinate scale used for fracture/detail samples.
- Skip only weight == 0.0. Any epsilon threshold changes the authored blend and is outside this candidate.
- Leave the existing true-triangle cap normal, normalized weights, back-face handling, color, and normal-combination formulas unchanged.

Likely limits: scanned and rounded surfaces commonly have nonzero weights on all axes. Dynamic branches may add cost without avoiding a lookup there. Benefits concentrate on exactly flat/axis-aligned surfaces. Native A/B timing and images are required; explicit and implicit derivative choices are not assumed to be bit-identical across GPU drivers.

Separate uniform-branch candidates: ground_surface uses AO=1 and never uses concept_grain, so height and grain lookups may be moved into !ground_surface work. For ground's fracture_mix=0, fracture albedo and normal contributions are zero. Branching by that uniform can avoid their lookups while preserving mathematical output. Compilers may already eliminate some dead uniform work, so no speedup is asserted.

Sources:
- Godot built-in functions: https://docs.godotengine.org/en/4.6/tutorials/shaders/shader_reference/shader_functions.html
- GLSL 4.60: https://registry.khronos.org/OpenGL/specs/gl/GLSLangSpec.4.60.html

No geology shader or runtime source has been modified for this investigation.
