# Prepared prop LOD resources

`anatomical_skull_lod.res` is a compressed 2,347,541-byte Godot ArrayMesh with the original 127,094-triangle close-view anatomy and six alternate index buffers down to 1,984 triangles. Its base vertex, normal, UV and index arrays are byte-identical to the production source after save/load. No runtime import or decimation is required.

The original [BodyParts3D attribution and license](../licenses/ANATOMICAL_SKELETON.md) apply to this derived resource. Source/resource hashes and generation evidence are in `anatomical_skull_lod.provenance.json`.

Regenerate explicitly with `BAKE_PROP_LODS=1 ./tests/run_headless_tests.sh prop_mesh_lod`. Normal test execution verifies the packaged resource without rebuilding it. Production `dark_fantasy_skull.gd` now loads this shared resource directly. Tests independently reconstruct the original source to verify the base geometry and confirm that the real production mesh includes the LOD indices.
