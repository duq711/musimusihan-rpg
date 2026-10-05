"""Cross-check raw-capture FK against Blender's bundled BVH import behavior.

Background Blender, no rendering, source writes, model assumptions or skin QA.
Only the small verification report is written. Source captures remain intact.
"""
import argparse
import json
import sys
from pathlib import Path

import bpy
from bpy_extras.io_utils import axis_conversion

sys.path.insert(0, str(Path(__file__).resolve().parent))
from labrador_pet_bvh import read_bvh


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--report", type=Path, required=True)
    args = parser.parse_args(sys.argv[sys.argv.index("--")+1:])
    bpy.ops.wm.read_factory_settings(use_empty=True)
    source_names = ("dog_idle_001.bvh", "dog_quad_walk_001.bvh", "dog_quad_run_001.bvh")
    coordinate = axis_conversion(from_forward="-Z", from_up="Y").to_4x4()
    results = []
    for filename in source_names:
        path = args.source / filename
        capture = read_bvh(path)
        bpy.ops.import_anim.bvh(filepath=str(path), axis_forward="-Z", axis_up="Y",
                                global_scale=.01, use_fps_scale=False,
                                update_scene_fps=True, frame_start=1,
                                rotate_mode="QUATERNION")
        rig = bpy.context.object
        samples = []
        for raw_frame in (0, len(capture.frames)//2, len(capture.frames)-1):
            bpy.context.scene.frame_set(raw_frame+1)
            bpy.context.view_layer.update()
            expected = capture.world_pose(raw_frame, coordinate, .01, position_mode="absolute")
            errors = {
                bone.name: ((rig.matrix_world @ bone.matrix).translation - expected[bone.name].translation).length
                for bone in rig.pose.bones
            }
            maximum = max(errors, key=errors.get)
            samples.append({"raw_frame": raw_frame, "bones": len(errors),
                            "max_position_error_m": errors[maximum], "worst_bone": maximum,
                            "pass": errors[maximum] <= .0002})
        results.append({"file": filename, "samples": samples, "pass": all(item["pass"] for item in samples)})
        print("SOURCE_FK_VERIFIED", filename, results[-1]["pass"], flush=True)
        bpy.data.objects.remove(rig, do_unlink=True)
    result = {
        "blender": bpy.app.version_string, "captures": len(results), "frames": sum(len(r["samples"]) for r in results),
        "joint_position_comparisons": sum(item["bones"] for r in results for item in r["samples"]),
        "tolerance_m": .0002, "pass": all(item["pass"] for item in results),
        "method": "Independent BVH hierarchy/channel FK versus Blender bundled BVH importer; source Y-up centimetres converted to Z-up metres.",
        "scope": "Source decode/coordinate verification only; downloaded model skin, retargeting, contact and visual quality remain unverified.",
        "results": results,
    }
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(result, indent=2)+"\n")
    print("SOURCE_VERIFICATION_COMPLETE", result["pass"], flush=True)
    if not result["pass"]:
        raise RuntimeError("Capture FK differs from Blender's bundled BVH importer")


if __name__ == "__main__":
    main()
