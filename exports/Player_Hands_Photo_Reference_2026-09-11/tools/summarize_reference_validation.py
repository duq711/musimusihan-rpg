"""Hash-check the final reference-hand evidence after direct visual approval.

This is a packaging gate, not a Blender/Godot runner. It never renders, bakes,
changes live assets or supplies missing approval from numeric test results.
"""
import argparse
import hashlib
import json
import re
import struct
from datetime import datetime, timezone
from pathlib import Path

TESTS = ("player_finger_joints", "player_hands_detailed", "player_hands_greybox",
         "player_arm", "weapon_hand_contacts", "chest_hands", "test_room_session")
PREVIEWS = {"player_finger_joints": 12, "player_hands_detailed": 6}
RENDERS = {"dorsum", "palm", "side", "dorsum_closeup", "palm_closeup"}
EXPECTED_PHOTO_SHA = "67536edf1860cd47984cd6b00ff9935a00a6c8c15226b40ad1276e6bba3e4af7"


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def read(path):
    return json.loads(Path(path).read_text())


def relative_file(root, name):
    path = (root / name).resolve()
    assert path.is_relative_to(root.resolve()) and path.is_file(), str(path)
    return path


def metadata_preservation(stage, model, build, independent):
    """Require actual preservation evidence before reusing prior native renders."""
    update = build.get("wrist_metadata_update")
    if not update:
        assert model.name != "final_03", "Final03 requires metadata-only preservation evidence"
        return None
    report_path = relative_file(model, update["report"])
    report = read(report_path)
    proof_path = relative_file(model, "metadata_preservation_independent_report.json")
    proof = read(proof_path)
    assert report["status"] == "metadata_only_payload_preservation_passed"
    assert proof["status"] == "passed" and proof["inputs_unchanged"]
    assert report["start_before"] == .014 and report["start_after"] == .028
    assert report["end_unchanged"] == .075 and report["version_unchanged"] == 1
    assert report["all_prior_recursive_files_sha_unchanged"] and report["no_bake_render_or_geometry_operation"]
    for path, expected in proof["verified_sha256"].items():
        assert digest(path) == expected, "Metadata-only preservation input changed: " + path
    geometry_path = Path(build["source"])
    assert geometry_path.parent.name == "geometry_05"
    assert digest(geometry_path) == build["source_sha256"] == report["geometry_blend"]["output_sha256"]
    assert independent["verified_sha256"][str(geometry_path.resolve())] == build["source_sha256"]
    for label, output in (("geometry_blend", geometry_path), ("final_blend", model / "bilateral_hands_reference.blend")):
        row, actual = report[label], proof["pairs"][label]
        assert digest(row["source"]) == row["source_sha256"] == actual["source_sha256"]
        assert digest(output) == row["output_sha256"] == actual["output_sha256"]
        assert row["all_except_start_property_exact"] and actual["all_other_properties_exact"]
        assert row["before_payload_signature"] == row["after_payload_signature"] == actual["shared_payload_signature"]
        assert actual["mesh_keys_weights_uv_materials_images_rest_pose_cameras_viewports_exact"]
        assert actual["lights_worlds_visibility_scene_members_exact"]
        assert len(row["changed_properties"]) == (4 if label == "geometry_blend" else 8)
        assert {r["object"] for r in row["changed_properties"]} == set(actual["changed_start_property_objects"])
        assert all("WristCuff" in r["object"] and r["before"] == .014 and r["after"] == .028 for r in row["changed_properties"])
    source_model = Path(report["final_blend"]["source"]).parent
    glbs = {}
    for side in ("left", "right"):
        name = f"{side}_hand_reference.glb"
        before = relative_file(source_model, name).read_bytes()
        after = relative_file(model, name).read_bytes()
        row = report["glbs"][side]
        assert digest(source_model / name) == row["source_sha256"] and digest(model / name) == row["output_sha256"]
        assert before[:12] == after[:12] and len(before) == len(after)
        size, kind = struct.unpack_from("<II", before, 12)
        assert kind == 0x4E4F534A and before[12:20] == after[12:20]
        expected = json.loads(before[20:20 + size])
        changed_nodes = []
        for index, node in enumerate(expected["nodes"]):
            props = node.get("extras", {})
            if "wrist_flex_start_z" in props:
                assert "WristCuff" in node["name"] and props["wrist_flex_start_z"] == .014
                assert props["wrist_flex_end_z"] == .075 and props["wrist_flex_version"] == 1
                props["wrist_flex_start_z"] = .028
                changed_nodes.append({"node": index, "name": node["name"]})
        assert len(changed_nodes) == 2 and changed_nodes == row["changed_nodes"]
        assert json.loads(after[20:20 + size]) == expected, "GLB JSON changes exceed the named cuff start"
        assert before[20 + size:] == after[20 + size:], "GLB binary payload changed"
        binary_sha = hashlib.sha256(after[20 + size:]).hexdigest()
        assert binary_sha == row["binary_chunk_sha256"]
        glbs[side] = {"whole_binary_chunk_sha256": binary_sha, "whole_binary_chunk_exact": True,
            "only_changed_json_nodes": changed_nodes}
    for name, expected in report["copied_payload_sha256"].items():
        assert digest(relative_file(model, name)) == digest(relative_file(source_model, name)) == expected
    old_build = read(relative_file(source_model, "material_report.json"))
    assert build["renders"] == old_build["renders"] and build["reference_pair"] == old_build["reference_pair"]
    native_files = [r["image"] for r in build["renders"].values()] + [build["reference_pair"]["image"]]
    assert len(native_files) == 6 and all(name in report["copied_payload_sha256"] for name in native_files)
    return {"passed": True, "model_iteration": model.name, "report": report_path.name, "report_sha256": digest(report_path),
        "independent_preservation_report": proof_path.name, "independent_report_sha256": digest(proof_path),
        "approved_geometry_sha256": build["source_sha256"], "start_before_m": .014, "start_after_m": .028,
        "end_unchanged_m": .075, "version_unchanged": 1, "glbs": glbs,
        "native_render_source_iteration": source_model.name,
        "native_renders_copied_exact": {name: report["copied_payload_sha256"][name] for name in native_files},
        "render_provenance": "Six actual native renders are reused byte-for-byte from the prior final02. Geometry, materials, images, pose, cameras, lighting and visibility are independently unchanged. The runtime-only cuff metadata requires fresh Godot captures."}


def wrist_weight_preservation(stage, model, build, independent):
    report_path = relative_file(model, build["wrist_weight_update"]["report"])
    report = read(report_path)
    assert report["status"] == "weight_and_metadata_patch_preservation_passed"
    assert report["flex_start_before"] == .028 and report["flex_start_after"] == .026
    assert report["flex_end_unchanged"] == .075 and report["flex_version_unchanged"] == 1
    assert report["source_final03_immutable"] and report["no_rebake_no_render_no_geometry_edit"]
    proof = independent["checks"]["wrist_weight_revision_preservation"]
    assert proof["status"] == "passed"
    source_model = Path(report["final"]["source"]).parent
    assert source_model.name == "final_03" and Path(build["source"]).parent.name == "geometry_06"
    prior = metadata_preservation(stage, source_model, read(source_model / "material_report.json"), read(source_model / "verification_report.json"))
    neutral_rows, changed_vertices = [], {}
    for label, target in (("geometry", Path(build["source"])), ("final", model / "bilateral_hands_reference.blend")):
        row, actual = report[label], proof["pairs"][label]
        assert digest(row["source"]) == row["source_sha256"] == actual["source_sha256"]
        assert digest(target) == row["output_sha256"] == actual["output_sha256"]
        assert row["geometry_keys_uv_materials_images_rest_pose_cameras_world_lights_exact"] and row["unrelated_mesh_weights_exact"]
        assert actual["authored_geometry_keys_uv_materials_images_rest_pose_cameras_lighting_visibility_exact"] and actual["non_hand_weights_exact"]
        assert row["before_frozen_signature"] == row["after_reopen_frozen_signature"] == actual["frozen_payload_signature"]
        assert set(row["metadata_objects"]) == set(actual["only_metadata_changed"])
        for side in ("left", "right"):
            checked = actual["approved_hand_weight_checks"][side]
            assert checked["maximum_formula_error"] == 0.0
            assert checked["changed_vertex_count"] == row["hands"][side]["changed_vertices"]
            assert checked["changed_native_godot_z_range_m"][0] > .010
            assert all(value == 0.0 for value in row["hands"][side]["boundary_morph_delta_max_m"].values())
            assert not row["hands"][side]["morphs_modified"]
            if label == "final":
                changed_vertices[side] = checked["changed_vertex_count"]
        for evaluated in actual["neutral_evaluated"].values():
            assert evaluated["maximum_position_error_m"] < 2e-7 and evaluated["maximum_unit_normal_error"] < 2e-5
            neutral_rows.append(evaluated)
    glbs = {}
    for side in ("left", "right"):
        name = f"{side}_hand_reference.glb"
        before, after = (source_model / name).read_bytes(), (model / name).read_bytes()
        row = report["glbs"][side]
        assert digest(source_model / name) == row["source_sha256"] and digest(model / name) == row["output_sha256"]
        assert len(before) == len(after) and before[:20] == after[:20]
        size, kind = struct.unpack_from("<II", before, 12)
        assert kind == 0x4E4F534A
        old_json = json.loads(before[20:20 + size])
        expected_json = json.loads(before[20:20 + size])
        changed_nodes = []
        for index, node in enumerate(expected_json["nodes"]):
            props = node.get("extras", {})
            if "wrist_flex_start_z" in props:
                assert "WristCuff" in node["name"] and props["wrist_flex_start_z"] == .028
                assert props["wrist_flex_end_z"] == .075 and props["wrist_flex_version"] == 1
                props["wrist_flex_start_z"] = .026
                changed_nodes.append(index)
        assert changed_nodes == row["metadata_nodes"] and len(changed_nodes) == 2
        assert json.loads(after[20:20 + size]) == expected_json
        base = 20 + size + 8
        assert before[20 + size:base] == after[20 + size:base]
        allowed = set()
        def accessor(index):
            data = old_json["accessors"][index]
            view = old_json["bufferViews"][data["bufferView"]]
            assert data["componentType"] == 5126
            width = {"VEC3": 12, "VEC4": 16}[data["type"]]
            return data["count"], base + view.get("byteOffset", 0) + data.get("byteOffset", 0), view.get("byteStride", width), width
        for node in old_json["nodes"]:
            if "Anatomical" not in node.get("name", "") or "mesh" not in node:
                continue
            for primitive in old_json["meshes"][node["mesh"]]["primitives"]:
                attributes = primitive["attributes"]
                count, positions, stride, unused = accessor(attributes["POSITION"])
                for index in range(count):
                    z = struct.unpack_from("<f", before, positions + index * stride + 8)[0]
                    if z <= .010:
                        continue
                    for semantic, acc in attributes.items():
                        if semantic.startswith("WEIGHTS_"):
                            n, start, step, width = accessor(acc)
                            assert n == count
                            allowed.update(range(start + index * step, start + index * step + width))
        declared = {i for start, end in row["allowed_binary_ranges_file_offsets"] for i in range(start, end)}
        assert declared == allowed and not row["joint_changes"], "Only eligible wrist-band WEIGHTS bytes may change"
        actual_changed = {i for i in range(base, len(before)) if before[i] != after[i]}
        assert actual_changed <= allowed
        declared_changed = {i for start, end in row["actual_changed_binary_ranges_file_offsets"] for i in range(start, end)}
        assert actual_changed == declared_changed
        a, b = bytearray(before[base:]), bytearray(after[base:])
        for index in allowed:
            a[index - base] = b[index - base] = 0
        assert a == b and hashlib.sha256(a).hexdigest() == row["masked_binary_sha256"]
        assert independent["checks"][side + "_glb"]["roundtrip"]["hand"]["named_weight_error"] < .000001
        glbs[side] = {"only_eligible_wrist_weight_bytes_changed": True, "joint_indices_unchanged": True,
            "all_other_binary_bytes_exact": True, "actual_changed_bytes": len(actual_changed),
            "masked_binary_sha256": row["masked_binary_sha256"]}
    for name, expected in report["copied_payload_sha256"].items():
        assert digest(relative_file(model, name)) == digest(relative_file(source_model, name)) == expected
    old_build = read(source_model / "material_report.json")
    assert build["renders"] == old_build["renders"] and build["reference_pair"] == old_build["reference_pair"]
    for name, expected in prior["native_renders_copied_exact"].items():
        assert digest(model / name) == expected
    return {"passed": True, "model_iteration": model.name, "source_model_iteration": source_model.name,
        "report": report_path.name, "report_sha256": digest(report_path),
        "prior_metadata_revision": prior, "approved_geometry_sha256": build["source_sha256"],
        "flex_start_m": .026, "flex_end_m": .075, "weight_ramp_start_m": .010, "pure_wrist_from_m": .018,
        "changed_skin_vertices": changed_vertices, "protected_finger_palm_weights_exact": True,
        "neutral_evaluated_maximum_position_error_m": max(r["maximum_position_error_m"] for r in neutral_rows),
        "neutral_evaluated_maximum_unit_normal_error": max(r["maximum_unit_normal_error"] for r in neutral_rows),
        "glbs": glbs, "native_render_source_iteration": prior["native_render_source_iteration"],
        "render_provenance": "Native final02 renders are copied byte-for-byte through final03/04. Skin weights intentionally differ in the approved wrist band. Authored geometry, keys, UV, materials/images, cameras, pose, lights, worlds and visibility are unchanged; independently measured neutral surface errors are recorded above. Fresh Godot captures validate the changed posed behavior."}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--model-iteration", default="final_01")
    parser.add_argument("--preview-iteration", required=True)
    parser.add_argument("--test-log", required=True, help="Final seven-test log, relative to this stage")
    parser.add_argument("--independent-report", default="verification_report.json", help="Relative to final model directory")
    parser.add_argument("--independent-log", required=True, help="Final Blender verifier log, relative to this stage")
    parser.add_argument("--validation-log", action="append", default=[], help="Additional actual import/preview logs to package, relative to stage")
    parser.add_argument("--visually-reviewed", action="store_true", help="Root has directly reviewed all native images and all eighteen current Godot captures")
    args = parser.parse_args()
    assert args.visually_reviewed, "Direct visual review must precede the packaging gate"
    stage = Path(__file__).resolve().parents[1]
    project = stage.parents[1]
    game = project / "godot-game"
    model = stage / "mac_output" / args.model_iteration
    independent_path = relative_file(model, args.independent_report)
    independent = read(independent_path)
    assert independent["status"] == "passed" and not independent["errors"]
    for path, expected in independent["verified_sha256"].items():
        assert digest(path) == expected, "Independent validation input changed: " + path
    model_paths = [model / "bilateral_hands_reference.blend"] + [model / f"{side}_hand_reference.glb" for side in ("left", "right")]
    model_hashes = {path.name: digest(path) for path in model_paths}
    for path in model_paths:
        assert independent["verified_sha256"][str(path.resolve())] == model_hashes[path.name]
    for side in ("left", "right"):
        assert model_hashes[f"{side}_hand_reference.glb"] == digest(game / f"assets/3d/player/hands_detailed/{side}_hand_detailed.glb"), "Game does not use the verified reference hand"

    photo = relative_file(stage, "reference/user_hand_photo.png")
    environment = read(stage / "baseline/environment.json")
    assert digest(photo) == environment["reference_sha256"] == EXPECTED_PHOTO_SHA
    preserved_path = stage / "baseline/preserved_artifacts.json"
    preserved = read(preserved_path)
    assert len(preserved) == 1888, "Unexpected previous-artifact preservation ledger"
    assert all(digest(project / path) == expected for path, expected in preserved.items()), "A prior deliverable changed"

    build_path = relative_file(model, "material_report.json")
    build = read(build_path)
    assert build["phase"] == "material"
    weight_revision = wrist_weight_preservation(stage, model, build, independent) if build.get("wrist_weight_update") else None
    metadata_revision = weight_revision["prior_metadata_revision"] if weight_revision else metadata_preservation(stage, model, build, independent)
    expected_build_status = "weights_corrected_pending_independent_and_game_validation" if weight_revision else ("metadata_updated_pending_independent_validation_and_game_review" if metadata_revision else "built_pending_visual_review")
    assert build["status"] == expected_build_status
    assert build["blend_sha256"] == model_hashes["bilateral_hands_reference.blend"]
    assert build["delivery_scene"]["reference_image_packed"]
    assert set(build["delivery_scene"]["kept_scenes"]) == {"Bilateral_Reference_Review", "Photo_Reference_Palm_And_Dorsum"}
    render_review = {}
    assert RENDERS <= set(build["renders"])
    for name, entry in build["renders"].items():
        path = relative_file(model, entry["image"])
        assert entry["actual_blender_render"] and not entry["clay_override"]
        assert digest(path) == entry["sha256"]
        render_review[name] = dict(entry, directly_visually_reviewed=True)
    pair = build["reference_pair"]
    assert pair["actual_blender_render"]
    assert digest(relative_file(model, pair["image"])) == pair["sha256"]
    render_review["reference_palm_and_dorsum"] = dict(pair, directly_visually_reviewed=True)
    for entry in render_review.values():
        entry["rendered_model_iteration"] = metadata_revision["native_render_source_iteration"] if metadata_revision else args.model_iteration
        entry["copied_after_metadata_only_change"] = metadata_revision is not None and weight_revision is None
        entry["copied_after_neutral_equivalent_wrist_weight_repair"] = weight_revision is not None

    padding_path = relative_file(model, "atlas_padding_report.json")
    padding = read(padding_path)
    assert padding["status"] == "passed" and [padding["width"], padding["height"]] == [4096, 4096]
    assert set(padding["maps"]) == {"basecolor", "normal", "roughness"}
    assert padding["surface_seed_pixels"] + padding["filled_background_pixels"] == 4096 * 4096
    texture_hashes = {}
    for channel, entry in padding["maps"].items():
        assert entry["all_existing_surface_pixels_exact"] and entry["changed_existing_surface_pixels"] == 0
        path = relative_file(model, f"reference_hands_{channel}.png")
        assert digest(path) == entry["output_sha256"]
        assert digest(relative_file(model, f"unfilled_atlas/reference_hands_{channel}.png")) == entry["source_sha256"]
        texture_hashes[path.name] = entry["output_sha256"]

    log_names = list(dict.fromkeys([args.test_log, args.independent_log] + args.validation_log))
    log_paths = {name: relative_file(stage, name) for name in log_names}
    headless = log_paths[args.test_log].read_text()
    assert "Headless validation: 7 passed, 0 failed." in headless
    assert "SCRIPT ERROR:" not in headless and "ERROR:" not in headless
    names = re.findall(r"^\[HEADLESS\]\s+([a-z0-9_]+)_test\.gd\s*$", headless, re.MULTILINE)
    assert len(names) == 7 and set(names) == set(TESTS)
    verifier_log = log_paths[args.independent_log].read_text()
    assert "REFERENCE_HANDS_VERIFICATION passed" in verifier_log
    assert "Traceback (most recent call last)" not in verifier_log

    previews, wrists, joins = {}, [], []
    wrist_captures = 0
    join_captures = 0
    for kind, count in PREVIEWS.items():
        folder = game / "artifacts/visual_qa" / kind / args.preview_iteration
        manifest_path = relative_file(folder, "capture_manifest.json")
        manifest = read(manifest_path)
        assert not manifest["failures"] and len(manifest["captures"]) == count
        assert manifest["display_driver"] == "embedded" and manifest["actual_renderer"] == "vulkan"
        assert manifest["expedition_inventory_and_cursor_preserved"] and manifest["sources_unchanged_during_capture"]
        for source, expected in manifest["source_sha256"].items():
            assert source.startswith("res://")
            assert digest(relative_file(game, source.removeprefix("res://"))) == expected
        captures = []
        for capture in manifest["captures"]:
            assert capture["passed"]
            assert digest(relative_file(folder, capture["image"])) == capture["image_sha256"]
            if capture.get("profile") == "greybox":
                assert kind == "player_hands_detailed" and capture["image"] == "free_hands_greybox.png"
                assert capture["same_pose_and_camera"]
            else:
                joined = capture["skin_cuff_joins"]
                assert joined["passed"] and len(joined["hands"]) >= 2
                for entry in joined["hands"]:
                    assert entry["passed"] and entry["sample_count"] >= 32
                    assert entry["maximum_source_gap_m"] < .0006
                    assert entry["maximum_actual_nearest_outer_gap_m"] < .001
                    assert entry["maximum_fit_added_gap_m"] < .00005 and entry["maximum_cuff_surface_shift_m"] < .00005
                    assert entry["support_triangles_outside_fixed_span"] == 0
                joins.extend(joined["hands"])
                join_captures += 1
            if "wrist_gpu_buffers" in capture:
                assert capture["wrist_gpu_buffers"]["passed"] and capture["actual_pbr_bindings"]["passed"]
                wrists.extend(capture["wrist_gpu_buffers"]["wrists"])
                wrist_captures += 1
            captures.append({"image": capture["image"], "sha256": capture["image_sha256"], "directly_visually_reviewed": True})
        previews[kind] = {"captures": count, "images": captures, "all_images_visually_reviewed": True,
            "all_inspections_passed": True, "source_sha256": manifest["source_sha256"],
            "manifest": f"godot_preview/{kind}/capture_manifest.json", "manifest_sha256": digest(manifest_path),
            "world_inventory_cursor_preserved": True, "renderer": "Vulkan", "display_driver": "embedded", "image_size": manifest["image_size"]}
    assert wrist_captures == 12 and wrists and all(entry["passed"] for entry in wrists)
    assert join_captures == 17 and joins, "Every current detailed capture must verify the actual skin/cuff junction"
    assert all(entry["invalid_tangents"] == 0 and entry["invalid_vertex_count"] == 0 and entry["minimum_jacobian_determinant"] > 0 for entry in wrists)

    summary = {"status": "passed", "completed_at": datetime.now(timezone.utc).isoformat(),
        "model_iteration": args.model_iteration, "preview_iteration": args.preview_iteration, "model_sha256": model_hashes,
        "reference_photo": {"file": "reference/user_hand_photo.png", "sha256": digest(photo), "unaltered_original": True, "packed_in_editable_scene": True},
        "blender_independent_validation": args.independent_report, "blender_independent_report_sha256": digest(independent_path),
        "approved_geometry_input": {"path": build["source"], "sha256": build["source_sha256"]},
        "material_report": "material_report.json", "material_report_sha256": digest(build_path), "blender_review": render_review,
        "metadata_only_revision": metadata_revision,
        "wrist_weight_revision": weight_revision,
        "headless": {"passed": 7, "failed": 0, "tests": list(TESTS), "log_sha256": digest(log_paths[args.test_log]),
            "warnings_recorded_in_log": [line for line in headless.splitlines() if line.startswith("WARNING:")]},
        "previews": previews, "preserved_prior_files": len(preserved), "all_prior_hashes_unchanged": True,
        "preservation_ledger_sha256": digest(preserved_path),
        "gpu_readback": {"capture_count": wrist_captures, "wrist_vertex_samples": sum(entry["vertex_count"] for entry in wrists),
            "max_position_error_m": max(entry["max_position_error_m"] for entry in wrists),
            "max_normal_error": max(entry["max_normal_error"] for entry in wrists),
            "minimum_jacobian": min(entry["minimum_jacobian_determinant"] for entry in wrists),
            "invalid_tangents": 0, "invalid_vertices": 0, "passed": True},
        "skin_cuff_join": {"passed": True, "capture_count": join_captures,
            "actual_skin_samples": sum(entry["sample_count"] for entry in joins),
            "maximum_actual_nearest_outer_gap_m": max(entry["maximum_actual_nearest_outer_gap_m"] for entry in joins),
            "maximum_fit_added_gap_m": max(entry["maximum_fit_added_gap_m"] for entry in joins),
            "maximum_cuff_surface_shift_m": max(entry["maximum_cuff_surface_shift_m"] for entry in joins),
            "support_triangles_outside_fixed_span": 0,
            "greybox_comparison": "One preserved greybox comparison has no new detailed cuff and is excluded; its identical pose and camera are checked."},
        "texture_review": {"actual_pbr_maps": ["basecolor", "normal", "roughness"], "resolution": [4096, 4096],
            "texture_sha256": texture_hashes, "padding_report_sha256": digest(padding_path),
            "authored_pixels_preserved_per_map": padding["surface_seed_pixels"], "blank_pixels_filled_per_atlas": padding["filled_background_pixels"],
            "photo_comparison_is_a_native_model_render": True, "native_review_lighting_is_separate_from_game_lighting": True},
        "validation_logs": log_names, "validation_log_sha256": {name: digest(path) for name, path in log_paths.items()},
        "tool_source_sha256": {str(path.relative_to(stage)): digest(path) for path in sorted((stage / "tools").iterdir()) if path.is_file() and path.suffix in (".py", ".cpp")},
        "portable_verifier_dependencies": ["verify_hands_realistic.py", "joint_verification_core.py", "reference_weight_signatures.py"],
        "visual_review_notes": read(stage / "visual_review.json"),
        "visual_review_notes_sha256": digest(stage / "visual_review.json"),
        "limitations": ["Numeric validation establishes deformation and data integrity; visual resemblance is a separate direct review recorded above.",
            "The full unrelated project test suite was not run.", "Read-only reproduction of the independent audit also needs the exact prior04 and approved-geometry input files named in its SHA ledger."]}
    destination = stage / "validation_summary.json"
    destination.write_text(json.dumps(summary, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({"status": "passed", "headless": 7, "gpu_captures": 18, "preserved_prior_files": len(preserved),
        "native_review_images": len(render_review), "summary_sha256": digest(destination)}, ensure_ascii=False))


if __name__ == "__main__":
    main()
