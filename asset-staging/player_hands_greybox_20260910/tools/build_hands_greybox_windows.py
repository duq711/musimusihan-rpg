"""Windows/background-only, non-destructive material greybox of production arms.

Run through run_windows.ps1. This duplicates and decimates production hand meshes
before their armature modifier; it is an unverified proportion/silhouette study.
No Blender work should be run on the Mac. No output is an observed result until
this script has run successfully on the Windows production machine.
"""

import argparse
import hashlib
import json
import math
import platform
import struct
import sys
from datetime import datetime, timezone
from pathlib import Path


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def glb_json(path):
    data = path.read_bytes()
    if data[:4] != b"glTF" or struct.unpack_from("<I", data, 4)[0] != 2:
        raise ValueError(f"Not a GLB v2 file: {path}")
    size, kind = struct.unpack_from("<II", data, 12)
    if kind != 0x4E4F534A:
        raise ValueError(f"GLB first chunk is not JSON: {path}")
    return json.loads(data[20:20 + size])


def glb_summary(path):
    doc = glb_json(path)
    pending = list(doc["scenes"][doc.get("scene", 0)].get("nodes", []))
    reachable = set()
    while pending:
        node_id = pending.pop()
        if node_id not in reachable:
            reachable.add(node_id)
            pending.extend(doc["nodes"][node_id].get("children", []))
    referenced = [doc["nodes"][i]["mesh"] for i in reachable if "mesh" in doc["nodes"][i]]
    triangles = sum(
        doc["accessors"][p["indices"]]["count"] // 3
        for i in referenced for p in doc["meshes"][i]["primitives"]
        if p.get("mode", 4) == 4 and "indices" in p
    )
    return {
        "bytes": path.stat().st_size, "sha256": sha256(path),
        "referenced_mesh_instances": len(referenced), "triangles": triangles,
        "skins": [[doc["nodes"][j].get("name", "") for j in s["joints"]]
                  for s in doc.get("skins", [])],
        "materials": [m.get("name", "") for m in doc.get("materials", [])],
        "textures": len(doc.get("textures", [])),
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input-dir", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--target-triangles", type=int, default=10000)
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:])
    if platform.system() != "Windows":
        raise SystemExit("Refusing production work: this builder runs on Windows only.")
    import bpy
    from mathutils import Vector
    if not bpy.app.background:
        raise SystemExit("Refusing interactive work: launch Blender with --background.")
    if args.target_triangles < 1000:
        raise SystemExit("Target must be at least 1,000 triangles per side.")
    source_dir, output = args.input_dir.resolve(), args.output_dir.resolve()
    inputs = {n: source_dir / f"{n}.glb"
              for n in ("left_arm", "right_arm", "gravebound_player")}
    for path in inputs.values():
        if not path.is_file():
            raise SystemExit(f"Required input missing: {path}")
        glb_json(path)
    if output == source_dir or source_dir in output.parents:
        raise SystemExit("Output must be outside the read-only input directory.")
    if output.exists() and (not output.is_dir() or any(output.iterdir())):
        raise SystemExit(f"Refusing nonempty output path: {output}")
    input_report = {n: glb_summary(p) for n, p in inputs.items()}
    output.mkdir(parents=True, exist_ok=True)
    # All guards above run before a destructive scene operation.
    bpy.ops.wm.read_factory_settings(use_empty=True)
    preview = bpy.context.scene
    preview.name = "Bilateral_Greybox_Review"

    def activate(scene):
        bpy.context.window.scene = scene
        bpy.context.view_layer.update()

    def isolated_import(label, path):
        scene = bpy.data.scenes.new(label)
        activate(scene)
        options = {"filepath": str(path), "import_pack_images": True,
                   "bone_heuristic": "TEMPERANCE", "merge_vertices": False}
        props = bpy.ops.import_scene.gltf.get_rna_type().properties.keys()
        bpy.ops.import_scene.gltf(**{k: v for k, v in options.items() if k in props})
        return scene, list(scene.objects)

    def bbox(objects):
        points = [o.matrix_world @ v.co for o in objects if o.type == "MESH"
                  for v in o.data.vertices]
        if not points:
            raise RuntimeError("Imported scene contains no mesh vertices")
        lo = [min(p[i] for p in points) for i in range(3)]
        hi = [max(p[i] for p in points) for i in range(3)]
        return {"min": lo, "max": hi, "size": [hi[i] - lo[i] for i in range(3)],
                "coordinate_system": "Blender world, meters; X right, Z up"}

    def mesh_signature(obj):
        digest = hashlib.sha256()
        for vertex in obj.data.vertices:
            digest.update(struct.pack("<3d", *vertex.co))
            for group in vertex.groups:
                digest.update(struct.pack("<Id", group.group, group.weight))
        for polygon in obj.data.polygons:
            digest.update(struct.pack("<I", len(polygon.vertices)))
            digest.update(struct.pack(f"<{len(polygon.vertices)}I", *polygon.vertices))
        return {"geometry_and_weights_sha256": digest.hexdigest(),
                "vertices": len(obj.data.vertices),
                "triangles": sum(len(p.vertices) - 2 for p in obj.data.polygons),
                "vertex_groups": [g.name for g in obj.vertex_groups]}

    def rig_signature(obj):
        return {b.name: {"parent": b.parent.name if b.parent else None,
                         "matrix_local": [list(row) for row in b.matrix_local],
                         "use_deform": b.use_deform,
                         "pose_basis": [list(row) for row in obj.pose.bones[b.name].matrix_basis]}
                for b in obj.data.bones}

    def weight_coverage(obj, bone_names):
        deform_ids = {g.index for g in obj.vertex_groups if g.name in bone_names}
        if not deform_ids:
            return {"rigged": False, "vertex_count": len(obj.data.vertices)}
        sums = [sum(g.weight for g in v.groups if g.group in deform_ids)
                for v in obj.data.vertices]
        return {"rigged": True, "vertex_count": len(sums),
                "weighted_vertices": sum(v > 1e-7 for v in sums),
                "weight_sum_min": min(sums), "weight_sum_max": max(sums),
                "finite": all(math.isfinite(v) for v in sums)}

    def gray(name, value):
        material = bpy.data.materials.new(name)
        material.use_nodes = True
        material.diffuse_color = (value, value, value, 1)
        material.node_tree.nodes.clear()
        shader = material.node_tree.nodes.new("ShaderNodeBsdfPrincipled")
        shader.inputs["Base Color"].default_value = (value, value, value, 1)
        shader.inputs["Metallic"].default_value = 0
        shader.inputs["Roughness"].default_value = 0.82
        terminal = material.node_tree.nodes.new("ShaderNodeOutputMaterial")
        material.node_tree.links.new(shader.outputs["BSDF"], terminal.inputs["Surface"])
        return material

    palette = [gray("Greybox_HandGlove", .42), gray("Greybox_WristCuff", .27),
               gray("Greybox_Sleeve", .18)]

    def material_index(obj):
        label = (obj.name + " " + obj.data.name).lower()
        if any(term in label for term in ("cuff", "wristconnection")):
            return 1
        if any(term in label for term in ("glove", "anatomicalhand")):
            return 0
        return 2

    def export_glb(path, scene, objects):
        activate(scene)
        bpy.ops.object.select_all(action="DESELECT")
        for obj in objects:
            obj.select_set(True)
        bpy.context.view_layer.objects.active = objects[0]
        options = {"filepath": str(path), "export_format": "GLB", "use_selection": True,
                   "export_yup": True, "export_materials": "EXPORT", "export_skins": True,
                   "export_animations": False, "export_apply": False,
                   "export_extras": True, "export_cameras": False, "export_lights": False}
        props = bpy.ops.export_scene.gltf.get_rna_type().properties.keys()
        bpy.ops.export_scene.gltf(**{k: v for k, v in options.items() if k in props})
        return glb_summary(path)

    report = {"status": "building", "created_utc": datetime.now(timezone.utc).isoformat(),
              "host": {"os": platform.platform(), "system": platform.system(),
                       "machine": platform.node(), "blender_binary": bpy.app.binary_path,
                       "blender_version": bpy.app.version_string, "background": bpy.app.background},
              "inputs": input_report, "hands": {},
              "scope": "Decimated bilateral neutral anatomy greybox; visual and deformation review pending",
              "preservation": "No mirroring, transform application or armature bake; source rigs retained",
              "decimation": {"target_triangles_per_side": args.target_triangles,
                             "minimum_ratio": .12, "mode": "COLLAPSE, before armature"},
              "runtime_caveat": "Neutral right_arm reference is not the currently equipped sword glove replacement",
              "materials": {m.name: list(m.diffuse_color) for m in palette},
              "standalone_origin": "Production source transforms retained, including wrist bone offset"}
    preview_objects = []
    wrist_origins = {}
    for side in ("left", "right"):
        source_scene, originals = isolated_import(f"Source_{side}_ReadOnly", inputs[f"{side}_arm"])
        rigs = [o for o in originals if o.type == "ARMATURE"]
        if len(rigs) != 1 or len(rigs[0].data.bones) != 16 or "wrist" not in rigs[0].data.bones:
            raise RuntimeError(f"{side}: expected one production 16-bone hand rig with wrist")
        rig_before = rig_signature(rigs[0])
        wrist_origins[side] = list(rigs[0].matrix_world @ rigs[0].data.bones["wrist"].head_local)
        native_bounds = bbox(originals)
        before_triangles = sum(mesh_signature(o)["triangles"] for o in originals if o.type == "MESH")
        ratio = min(1.0, max(.12, args.target_triangles / max(before_triangles, 1)))
        output_scene = bpy.data.scenes.new(f"Export_{side}_NativeOrigin")
        copies = {}
        for obj in originals:
            clone = obj.copy()
            if obj.data is not None:
                clone.data = obj.data.copy()
            clone.name = f"{side}_greybox_{obj.name}"
            output_scene.collection.objects.link(clone)
            copies[obj] = clone
        mesh_report = []
        activate(output_scene)
        for obj, clone in copies.items():
            clone.parent = copies.get(obj.parent)
            clone.matrix_parent_inverse = obj.matrix_parent_inverse.copy()
            clone.matrix_basis = obj.matrix_basis.copy()
            for modifier in clone.modifiers:
                if modifier.type == "ARMATURE":
                    modifier.object = copies.get(modifier.object, modifier.object)
            for constraint in clone.constraints:
                if hasattr(constraint, "target") and constraint.target in copies:
                    constraint.target = copies[constraint.target]
            if obj.type == "MESH":
                before, after = mesh_signature(obj), mesh_signature(clone)
                if before != after:
                    raise RuntimeError(f"Geometry or weights changed: {obj.name}")
                coverage_before = weight_coverage(clone, rig_before)
                bpy.ops.object.select_all(action="DESELECT")
                clone.select_set(True)
                bpy.context.view_layer.objects.active = clone
                modifier = clone.modifiers.new("Greybox_Collapse", "DECIMATE")
                modifier.decimate_type = "COLLAPSE"
                modifier.ratio = ratio
                modifier.use_collapse_triangulate = True
                bpy.ops.object.modifier_move_to_index(modifier=modifier.name, index=0)
                bpy.ops.object.modifier_apply(modifier=modifier.name)
                after = mesh_signature(clone)
                coverage_after = weight_coverage(clone, rig_before)
                if coverage_before["rigged"]:
                    if (not coverage_after.get("finite") or
                            coverage_after["weighted_vertices"] != coverage_after["vertex_count"] or
                            coverage_after["weight_sum_min"] < .98 or
                            coverage_after["weight_sum_max"] > 1.02):
                        raise RuntimeError(f"Decimation damaged skin weight coverage: {obj.name}")
                if before["vertex_groups"] != after["vertex_groups"]:
                    raise RuntimeError(f"Decimation changed vertex group names: {obj.name}")
                category = material_index(obj)
                clone.data.materials.clear()
                clone.data.materials.append(palette[category])
                for polygon in clone.data.polygons:
                    polygon.material_index = 0
                mesh_report.append({"source_name": obj.name, "output_name": clone.name,
                                    "gray_material": palette[category].name,
                                    "before": before, "after": after,
                                    "weight_coverage_before": coverage_before,
                                    "weight_coverage_after": coverage_after})
        clone_rig = copies[rigs[0]]
        if rig_signature(clone_rig) != rig_before:
            raise RuntimeError(f"Rest skeleton or pose changed: {side}")
        activate(output_scene)
        generated = list(copies.values())
        reduced_bounds = bbox(generated)
        bound_drift = max(abs(reduced_bounds[k][i] - native_bounds[k][i])
                          for k in ("min", "max") for i in range(3))
        if bound_drift > max(native_bounds["size"]) * .03:
            raise RuntimeError(f"Decimation moved silhouette bounds over 3%: {side}")
        standalone = export_glb(output / f"{side}_hand_greybox.glb", output_scene, generated)
        if len(standalone["skins"]) != 1 or set(standalone["skins"][0]) != set(rig_before):
            raise RuntimeError(f"Export lost skeleton joints: {side}")
        if standalone["textures"]:
            raise RuntimeError(f"Greybox export unexpectedly contains textures: {side}")
        report["hands"][side] = {"source_aabb": native_bounds, "reduced_aabb": reduced_bounds,
                                 "max_bound_drift_m": bound_drift, "wrist_origin": wrist_origins[side],
                                 "rig_bones": rig_before, "meshes": mesh_report,
                                 "export": standalone, "decimate_ratio": ratio,
                                 "triangles_before": before_triangles,
                                 "triangle_ratio_actual": standalone["triangles"] / before_triangles}
        # Preview-only parent translates complete object trees. Standalone exports
        # above retain the exact native origins; no source or child transform changes.
        activate(preview)
        holder = bpy.data.objects.new(f"{side.upper()}_PreviewTranslationOnly", None)
        holder["purpose"] = "Display spacing only; absent from standalone export"
        preview.collection.objects.link(holder)
        preview_objects.append(holder)
        for obj in generated:
            preview.collection.objects.link(obj)
            output_scene.collection.objects.unlink(obj)
            if obj.parent is None:
                obj.parent = holder
            preview_objects.append(obj)
        gap = .12
        holder.location.x = (-gap / 2 - native_bounds["max"][0] if side == "left"
                             else gap / 2 - native_bounds["min"][0])
        report["hands"][side]["preview_translation"] = list(holder.location)
        bpy.data.scenes.remove(output_scene)
    activate(preview)
    report["combined"] = export_glb(output / "both_hands_greybox_preview.glb", preview, preview_objects)
    report["combined"]["native_origin_compatible"] = False
    report["combined"]["purpose"] = "Side-by-side review; runtime imports use the standalone GLBs"

    # Preserve the full current player as a separate read-only reference scene in
    # the editable .blend; it cannot leak into the hand exports or hand renders.
    context_scene, context_objects = isolated_import("Current_Player_Scale_Reference", inputs["gravebound_player"])
    report["player_reference"] = {"aabb": bbox(context_objects),
                                  "scene": context_scene.name,
                                  "purpose": "Current-player proportion reference at native scale"}
    activate(preview)
    bounds = bbox(preview_objects)
    center = Vector([(bounds["min"][i] + bounds["max"][i]) / 2 for i in range(3)])
    span = max(bounds["size"])
    world = bpy.data.worlds.new("Greybox_Review_World")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (.09, .09, .09, 1)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = .7
    preview.world = world
    for name, offset, energy, size in (
        ("Key", (1, -1, 2), 350, 2), ("Fill", (-1, 1, 1), 230, 2),
        ("Rim", (0, 2, -1), 200, 1.5),
    ):
        lamp = bpy.data.lights.new(name, "AREA")
        lamp.energy, lamp.shape, lamp.size = energy, "DISK", size
        obj = bpy.data.objects.new(name, lamp)
        preview.collection.objects.link(obj)
        obj.location = center + Vector(offset) * max(span, .6)
        obj.rotation_euler = (center - obj.location).to_track_quat("-Z", "Y").to_euler()
    camera_data = bpy.data.cameras.new("Review_Camera")
    camera = bpy.data.objects.new("Review_Camera", camera_data)
    preview.collection.objects.link(camera)
    preview.camera = camera
    camera_data.type = "ORTHO"
    camera_data.ortho_scale = span * 1.28
    camera_data.clip_start, camera_data.clip_end = .001, 100
    preview.render.engine = "CYCLES"
    preview.cycles.device = "CPU"
    preview.cycles.samples = 32
    preview.render.resolution_x, preview.render.resolution_y = 1200, 1200
    preview.render.resolution_percentage = 100
    preview.render.image_settings.file_format = "PNG"
    preview.render.film_transparent = False
    # The production glTF Y-up conversion places the hands in Blender XY, fingers
    # toward +Y and the back of the hand toward +Z. Labels require visual review.
    views = {"dorsum": (0, 0, 1), "palm": (0, 0, -1), "side": (1, 0, 0)}
    report["renders"] = {}
    for name, direction in views.items():
        holders = [o for o in preview_objects if o.name.endswith("_PreviewTranslationOnly")]
        if name == "side":
            # +X would otherwise obscure the far hand. Stagger only the review
            # holders vertically; this happens after exports and is restored below.
            for index, holder in enumerate(holders):
                holder.location.z = (index * 2 - 1) * span * .4
            bpy.context.view_layer.update()
        view_bounds = bbox(preview_objects)
        view_center = Vector([(view_bounds["min"][i] + view_bounds["max"][i]) / 2 for i in range(3)])
        view_span = max(view_bounds["size"])
        camera_data.ortho_scale = view_span * 1.28
        camera.location = view_center + Vector(direction) * max(view_span * 3, 2)
        camera.rotation_euler = (view_center - camera.location).to_track_quat("-Z", "Y").to_euler()
        preview.render.filepath = str(output / f"both_hands_{name}.png")
        bpy.ops.render.render(write_still=True)
        report["renders"][name] = {"file": Path(preview.render.filepath).name,
                                    "camera_world_direction": direction,
                                    "layout": "vertically staggered" if name == "side" else "bilateral",
                                    "requires_visual_review": True}
        for holder in holders:
            holder.location.z = 0
        bpy.context.view_layer.update()
    camera_data.ortho_scale = span * 1.28
    camera.location = center + Vector(views["dorsum"]) * max(span * 3, 2)
    camera.rotation_euler = (center - camera.location).to_track_quat("-Z", "Y").to_euler()
    bpy.ops.wm.save_as_mainfile(filepath=str(output / "bilateral_hands_greybox.blend"))
    for name, path in inputs.items():
        if sha256(path) != input_report[name]["sha256"]:
            raise RuntimeError(f"Source file changed during build: {name}")
    report["status"] = "built_pending_visual_and_Godot_review"
    report["outputs"] = {p.name: {"bytes": p.stat().st_size, "sha256": sha256(p)}
                         for p in output.iterdir() if p.is_file()}
    (output / "build_report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print("GREYBOX_BUILD_COMPLETE", output)


if __name__ == "__main__":
    main()
