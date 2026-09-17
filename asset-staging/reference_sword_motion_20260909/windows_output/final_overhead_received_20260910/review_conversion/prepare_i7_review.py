"""Create a compact review projection from preserved i7 data, without authoring.

All writes are restricted to this transfer staging directory. Existing iteration
files and the established converter/schema remain immutable.
"""
from __future__ import annotations
import hashlib
import json
from pathlib import Path
import subprocess
import sys


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read(path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def write_once(path, content):
    if path.exists() and path.read_bytes() != content:
        raise FileExistsError(f"Preserve different existing staging file: {path}")
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(content)


def main():
    own = Path(__file__).resolve().parent
    staging = own.parent
    root = own.parents[2]
    assert staging == root / "thread_transfer_latest_v1/staging"
    i7 = root / "output/iteration_07"
    i4_blend = root / "output/iteration_04/Overhead_Review.blend"
    original_glb = root.parent / "sword_hold_long_grip/model/SwordHold_Static.glb"
    base_converter = root / "contracts/build_review.py"
    schema = root / "contracts/overhead_review.schema.json"
    sidecar_path = i7 / "arm_pose_samples.json"
    actual_execution = i7 / "authoring/execution.json"
    actual_log = i7 / "authoring/execution.log"
    finish_path = i7 / "surface_finish_report.json"
    finish = read(finish_path)
    raw = read(sidecar_path)
    if raw["status"] != "authored_windows_surface_finished_output" or raw["surface_finish"]["method"] != "continuous_sleeve_skin":
        raise ValueError("Expected preserved finished i7 continuous skin sidecar")
    if raw["rig"]["skin_count"] != 1 or raw["surface_finish"]["bone_count"] != 7:
        raise ValueError("Finished skin contract differs from the latest i7")
    protected = finish["protected_source_sha256"]
    if protected[str(i4_blend)] != sha(i4_blend):
        raise ValueError("Actual i7 Blender input no longer matches its execution report")
    if finish["artifacts"][sidecar_path.name]["sha256"] != sha(sidecar_path):
        raise ValueError("Actual finalization report does not match the i7 raw sidecar")

    saved_godot = root / "verification/godot_final/iteration_07_attempt_02/godot_playback_validation.json"
    runtime = read(saved_godot)
    if runtime["status"] != "pass" or runtime["unique_skin_resources"] != 1 or runtime["skinned_mesh_instance_count"] != 3:
        raise ValueError("Preserved Godot runtime skin evidence is missing or incompatible")
    if runtime["skeleton_inventory"][0]["bone_count"] != 7:
        raise ValueError("Preserved Godot runtime did not contain seven sleeve bones")
    glb_path = i7 / "Overhead_Review.glb"
    if sha(glb_path) != finish["artifacts"][glb_path.name]["sha256"]:
        raise ValueError("Saved final GLB differs from its finalization report")
    input_files = [base_converter, schema, i4_blend, original_glb, sidecar_path,
                   actual_execution, actual_log, finish_path, glb_path, saved_godot]
    inputs_before = {str(path): sha(path) for path in input_files}

    converter_text = base_converter.read_text(encoding="utf-8")
    old_note = "Incomplete one-action Windows review. Actual evaluated values are projected without rounding or coordinate changes. Part matrices and raw samples remain in arm_pose_samples.json. Never install this file as the production motion manifest. "
    new_note = ("Lossless review projection of the latest finished iteration_07, exactly one 1.55-second overhead. "
                "The eight controller samples and joints preserve the approved i4 trajectory. "
                "The finished continuous sleeve additionally REQUIRES the complete final GLB hierarchy: one Skin, "
                "seven sleeve bones, bind transforms, the overhead animation, and three skinned meshes "
                "(RightArm_ContinuousSleeve_Surface, RightArm_Forearm_Surface, RightArm_WristCuff_Surface). "
                "This review JSON and its three part matrices CANNOT reproduce the finished skin; "
                "do not substitute rigid part transforms for the skinned surface. Actual sample values are not rounded or transformed. "
                "The provenance is the actual i7 finalization run, whose direct Blender input was the preserved i4 blend. "
                "Do not install this review file as an eight-clip production motion manifest. ")
    replacements = [
        ('SOURCE_BLEND_SHA = "9555a83ca473801cc23e239360013cc9ec656a8235d679cbd9c8309c3de6a1f0"',
         f'SOURCE_BLEND_SHA = "{sha(i4_blend)}"'),
        ('"status": "authored_windows_output",', '"status": "authored_windows_surface_finished_output",'),
        ('    parser.add_argument("--execution", required=True, type=Path)',
         '    parser.add_argument("--execution", required=True, type=Path)\n'
         '    parser.add_argument("--authoring-log", required=True, type=Path)'),
        ('    authoring = read_json(authoring_path)',
         '    authoring = read_json(authoring_path)\n'
         '    import re\n'
         '    log_text = args.authoring_log.read_text(encoding="utf-8", errors="replace")\n'
         '    version_match = re.search(r"^Blender ([^\\r\\n]+?) \\(hash ", log_text, re.MULTILINE)\n'
         '    if version_match is None:\n'
         '        raise ValueError("Actual finalization log lacks a Blender version line")\n'
         '    authoring["blender_version"] = version_match.group(1)'),
        (old_note, new_note),
        ('json.dumps(data, ensure_ascii=False, indent=2, allow_nan=False)',
         'json.dumps(data, ensure_ascii=False, separators=(",", ":"), allow_nan=False)'),
        ('"maxima": maxima, "frame_audits": frame_audits,',
         '"maxima": maxima, "all_187_frames_validated": True, "per_frame_audit_rows_omitted_for_transfer": True,'),
        ('args.output.with_name("overhead_review_validation.json")',
         'args.output.with_name("overhead_review_validation_compact.json")'),
        ('"Part transforms are retained in the raw sidecar, not inserted into the motion track schema."',
         '"Part transforms are retained in the raw sidecar, not inserted into the motion track schema.",\n'
         '                         "Final i7 surface playback requires the complete Skin/bind/seven-bone hierarchy and three skinned meshes; review JSON alone is insufficient."'),
        ('"authoring_report_sha256": sha256(authoring_path),',
         '"authoring_report_sha256": sha256(authoring_path),\n'
         '              "authoring_log_sha256": sha256(args.authoring_log),\n'
         '              "source_status": raw["status"],\n'
         '              "finished_skin_required": True, "finished_skin_count": 1,\n'
         '              "finished_skin_bones": 7, "finished_skinned_meshes": 3,'),
    ]
    for old, new in replacements:
        count = converter_text.count(old)
        if count != 1:
            raise ValueError(f"Expected one precise converter adaptation point, got {count}: {old[:100]}")
        converter_text = converter_text.replace(old, new, 1)
    adapted = own / "build_review_i7.py"
    write_once(adapted, converter_text.encode("utf-8"))
    write_once(own / "overhead_review.schema.json", schema.read_bytes())
    for source, name in [(actual_execution, "execution.json"), (actual_log, "execution.log"), (finish_path, "surface_finish_report.json")]:
        write_once(own / "provenance" / name, source.read_bytes())

    output = staging / "overhead_review.json"
    argv = [sys.executable, str(adapted), "--samples", str(sidecar_path), "--execution", str(actual_execution),
            "--authoring-report", str(finish_path), "--authoring-log", str(actual_log),
            "--source-blend", str(i4_blend), "--source-glb", str(original_glb), "--output", str(output),
            "--shield-contract", str(root / "contracts/shield_idle_local_contract.json"),
            "--shield-confirmation", str(root / "contracts/shield_idle_mac_confirmation_01.json"),
            "--allow-local-shield-baseline",
            "--artifact", "execution_log=" + str(own / "provenance/execution.json"),
            "--artifact", "execution_log=" + str(own / "provenance/execution.log"),
            "--artifact", "validation_report=" + str(own / "provenance/surface_finish_report.json")]
    result = subprocess.run(argv, cwd=root, capture_output=True, text=True, encoding="utf-8")
    if result.returncode != 0:
        raise RuntimeError(result.stdout + result.stderr)
    document = read(output)
    # Independently compare every projected value, not just a rounding tolerance.
    for name in ("sword", "shield"):
        expected = [{"time_seconds": frame["time_seconds"], "position": frame[name]["position"],
                     "rotation_xyzw": frame[name]["rotation_xyzw"]} for frame in raw["frames"]]
        if document["clips"]["overhead"]["tracks"][name] != expected:
            raise ValueError("Projection changed actual raw sample values")
    expected_joints = [{"time_seconds": frame["time_seconds"], **{key: frame["right_arm"][key] for key in ("shoulder", "elbow", "wrist")}} for frame in raw["frames"]]
    if document["right_arm"] != expected_joints:
        raise ValueError("Projection changed actual raw joint values")
    inputs_after = {str(path): sha(path) for path in input_files}
    if inputs_before != inputs_after:
        raise ValueError("A protected input changed during the read-only projection")
    requirements = {
        "status": "integration_requirements_for_finished_i7",
        "clip_id": "overhead", "clip_count": 1, "sample_count": 187, "sample_hz": 120, "duration_seconds": 1.55,
        "review_json_is_not_a_complete_surface_animation": True,
        "required_final_glb_sha256": sha(glb_path), "required_final_glb_bytes": glb_path.stat().st_size,
        "required_glb_hierarchy": {"skin_count": 1, "skeleton_count": 1, "bone_count": 7,
                                   "bones": [entry["name"] for entry in runtime["skeleton_inventory"][0]["bones"]],
                                   "skinned_meshes": [entry["mesh"] for entry in runtime["skin_inventory"]],
                                   "preserve_bind_transforms": True, "preserve_animation": "overhead"},
        "raw_sidecar_sha256": sha(sidecar_path), "raw_sidecar_bytes": sidecar_path.stat().st_size,
        "source_status": raw["status"],
        "direct_blender_input": {"path": str(i4_blend), "sha256": sha(i4_blend)},
        "original_godot_model_sha256": sha(original_glb),
        "saved_godot_runtime_validation": {"sha256": sha(saved_godot), "status": runtime["status"],
                                            "samples_checked": runtime["samples_checked"],
                                            "cpu_skin_probe_max_error_m": runtime["maxima"]["cpu_skin_probe_error_m"]},
        "notes": "No new motion was authored. The one-clip review schema cannot carry the complete skinned sleeve deformation. The full final GLB or equivalent preserved skin/bind/bone animation data is required; the small JSON alone is not the finished surface."
    }
    write_once(staging / "i7_skin_integration_requirements.json", (json.dumps(requirements, ensure_ascii=False, separators=(",", ":"))+"\n").encode("utf-8"))
    conversion = {"status": "pass", "operation": "lossless_saved_i7_review_projection_no_authoring", "base_converter_sha256": sha(base_converter),
                  "adapted_converter_sha256": sha(adapted), "source_schema_sha256": sha(schema),
                  "source_files_unchanged": True, "inputs_before": inputs_before, "inputs_after": inputs_after,
                  "converter_argv": argv, "converter_exit_code": result.returncode,
                  "all_projected_numbers_equal_raw": True,
                  "outputs": [{"name": path.name, "bytes": path.stat().st_size, "sha256": sha(path)} for path in
                              [output, staging / "overhead_review_validation_compact.json", staging / "i7_skin_integration_requirements.json"]]}
    write_once(own / "conversion_provenance.json", (json.dumps(conversion, ensure_ascii=False, separators=(",", ":"))+"\n").encode("utf-8"))
    print(json.dumps({"status": "pass", "outputs": conversion["outputs"], "source_files_unchanged": True}, ensure_ascii=False))


if __name__ == "__main__":
    main()
