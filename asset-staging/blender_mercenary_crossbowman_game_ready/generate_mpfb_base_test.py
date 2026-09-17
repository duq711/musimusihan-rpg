"""Create an isolated MPFB/Rigify male base test in Blender 5.2.

This script intentionally writes only MPFB test artifacts.  It does not touch the
existing mercenary generator or final GLB.

Validated headless invocation on this machine::

    env \
      BLENDER_USER_RESOURCES=/tmp/mpfb-audit.cGwktn \
      MPFB_SYSTEM_ASSETS_ZIP=/tmp/mpfb-audit.cGwktn/makehuman_system_assets_cc0.zip \
      /Applications/Blender.app/Contents/MacOS/Blender \
      --background --python generate_mpfb_base_test.py

MPFB 2.0.17 must be enabled in the selected Blender user-resources directory.
The optional MakeHuman system asset pack is CC0 and supplies the 2K preview skin,
eyes, brows and short hair.  The production character still needs authored 4K
skin maps and reference-specific hair/beard/clothing.
"""

from __future__ import annotations

import importlib
import json
import math
import os
import sys
import zipfile
from pathlib import Path

import bpy
from mathutils import Matrix, Vector


SCRIPT_DIR = Path(__file__).resolve().parent
PREVIEW_DIR = SCRIPT_DIR / "previews"
RUNTIME_ASSET_DIR = SCRIPT_DIR / "_mpfb_cc0_preview_assets"
BLEND_PATH = SCRIPT_DIR / "mpfb_base_test.blend"
SUMMARY_PATH = SCRIPT_DIR / "mpfb_base_test_summary.json"

DEFAULT_SYSTEM_ASSET_ZIP = Path(
    "/tmp/mpfb-audit.cGwktn/makehuman_system_assets_cc0.zip"
)
SYSTEM_ASSET_ZIP = Path(
    os.environ.get("MPFB_SYSTEM_ASSETS_ZIP", str(DEFAULT_SYSTEM_ASSET_ZIP))
).expanduser()


def log(message: str) -> None:
    print(f"[MPFB BASE TEST] {message}", flush=True)


def load_mpfb_services():
    """Find the enabled extension regardless of its Blender repository id."""

    package_candidates: list[str] = []

    for addon_name in bpy.context.preferences.addons.keys():
        if addon_name == "mpfb" or addon_name.endswith(".mpfb"):
            package_candidates.append(addon_name)

    for module_name in sys.modules:
        if module_name == "mpfb" or module_name.endswith(".mpfb"):
            package_candidates.append(module_name)

    package_candidates.extend(
        [
            "bl_ext.user_default.mpfb",
            "bl_ext.blender_org.mpfb",
            "mpfb",
        ]
    )

    errors: list[str] = []
    for package_name in dict.fromkeys(package_candidates):
        try:
            human_module = importlib.import_module(
                f"{package_name}.services.humanservice"
            )
            target_module = importlib.import_module(
                f"{package_name}.services.targetservice"
            )
            rig_module = importlib.import_module(
                f"{package_name}.services.rigservice"
            )
            object_module = importlib.import_module(
                f"{package_name}.services.objectservice"
            )
            log(f"Using MPFB package {package_name}")
            return (
                human_module.HumanService,
                target_module.TargetService,
                rig_module.RigService,
                object_module.ObjectService,
            )
        except Exception as exc:  # Try the next possible extension package.
            errors.append(f"{package_name}: {exc}")

    joined = "\n  ".join(errors)
    raise RuntimeError(
        "MPFB is not enabled in this Blender profile. Run with "
        "BLENDER_USER_RESOURCES=/tmp/mpfb-audit.cGwktn or install/enable MPFB "
        f"2.0.17 first. Import attempts:\n  {joined}"
    )


def enable_rigify() -> None:
    if "rigify" not in bpy.context.preferences.addons:
        result = bpy.ops.preferences.addon_enable(module="rigify")
        if "FINISHED" not in result:
            raise RuntimeError(f"Could not enable bundled Rigify: {result}")
    log("Rigify enabled")


def clear_scene() -> None:
    if bpy.context.mode != "OBJECT":
        bpy.ops.object.mode_set(mode="OBJECT")
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj, do_unlink=True)
    for collection in list(bpy.data.collections):
        if collection.users == 0:
            bpy.data.collections.remove(collection)


def extract_preview_assets() -> dict[str, Path]:
    """Extract only the small CC0 subset used by this test."""

    if not SYSTEM_ASSET_ZIP.is_file():
        log(
            f"CC0 system asset pack not found at {SYSTEM_ASSET_ZIP}; "
            "using a procedural skin fallback without hair/eye assets"
        )
        return {}

    wanted_prefixes = (
        "skins/middleage_caucasian_male/",
        "eyes/high-poly/",
        "eyes/materials/brown.",
        "eyes/materials/brown_eye.",
        "hair/short02/",
        "eyebrows/eyebrow009/",
    )

    RUNTIME_ASSET_DIR.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(SYSTEM_ASSET_ZIP) as archive:
        for member in archive.namelist():
            if member.startswith(wanted_prefixes):
                destination = RUNTIME_ASSET_DIR / member
                if not destination.exists():
                    archive.extract(member, RUNTIME_ASSET_DIR)

    paths = {
        "skin": RUNTIME_ASSET_DIR
        / "skins/middleage_caucasian_male/middleage_caucasian_male.mhmat",
        "eyes": RUNTIME_ASSET_DIR / "eyes/high-poly/high-poly.mhclo",
        "hair": RUNTIME_ASSET_DIR / "hair/short02/short02.mhclo",
        "brows": RUNTIME_ASSET_DIR
        / "eyebrows/eyebrow009/eyebrow009.mhclo",
    }
    present = {key: value for key, value in paths.items() if value.is_file()}
    log(
        "Prepared CC0 preview assets: "
        + ", ".join(f"{key}={path}" for key, path in present.items())
    )
    return present


def create_fallback_skin_material(body: bpy.types.Object) -> None:
    material = bpy.data.materials.new("MPFB_Preview_Skin")
    material.use_nodes = True
    nodes = material.node_tree.nodes
    links = material.node_tree.links
    nodes.clear()

    output = nodes.new("ShaderNodeOutputMaterial")
    shader = nodes.new("ShaderNodeBsdfPrincipled")
    noise = nodes.new("ShaderNodeTexNoise")
    bump = nodes.new("ShaderNodeBump")

    shader.inputs["Base Color"].default_value = (0.34, 0.16, 0.095, 1.0)
    shader.inputs["Roughness"].default_value = 0.52
    if "Subsurface Weight" in shader.inputs:
        shader.inputs["Subsurface Weight"].default_value = 0.07
    noise.inputs["Scale"].default_value = 95.0
    noise.inputs["Detail"].default_value = 4.0
    noise.inputs["Roughness"].default_value = 0.7
    bump.inputs["Strength"].default_value = 0.09
    bump.inputs["Distance"].default_value = 0.002

    links.new(noise.outputs["Fac"], bump.inputs["Height"])
    links.new(bump.outputs["Normal"], shader.inputs["Normal"])
    links.new(shader.outputs["BSDF"], output.inputs["Surface"])
    body.data.materials.clear()
    body.data.materials.append(material)


def create_macro_profile(TargetService) -> dict:
    profile = TargetService.get_default_macro_info_dict()
    profile.update(
        {
            "gender": 1.0,
            "age": 0.62,
            "muscle": 0.62,
            "weight": 0.55,
            "proportions": 0.52,
            # Calibrated after the face targets/T-pose bake to yield about 1.78 m.
            "height": 0.553,
            "cupsize": 0.0,
            "firmness": 0.5,
        }
    )
    profile["race"].update(
        {"caucasian": 1.0, "african": 0.0, "asian": 0.0}
    )
    return profile


def apply_reference_direction_face_targets(body, TargetService) -> list[dict]:
    """Bias the neutral MPFB face toward the rugged, broad male reference."""

    target_stack = [
        {"target": "head-square", "value": 0.48},
        {"target": "head-scale-horiz-incr", "value": 0.10},
        {"target": "forehead-temple-incr", "value": 0.08},
        {"target": "chin-width-incr", "value": 0.36},
        {"target": "chin-bones-incr", "value": 0.22},
        {"target": "chin-prominent-incr", "value": 0.22},
        {"target": "chin-prognathism-incr", "value": 0.06},
        {"target": "nose-scale-depth-incr", "value": 0.18},
        {"target": "nose-width1-incr", "value": 0.15},
        {"target": "nose-width2-incr", "value": 0.12},
        {"target": "nose-hump-incr", "value": 0.12},
        {"target": "eyebrows-angle-down", "value": 0.18},
        {"target": "eyebrows-trans-forward", "value": 0.10},
        {"target": "l-cheek-bones-incr", "value": 0.11},
        {"target": "r-cheek-bones-incr", "value": 0.11},
        {"target": "l-eye-bag-incr", "value": 0.08},
        {"target": "r-eye-bag-incr", "value": 0.08},
        {"target": "mouth-scale-horiz-incr", "value": 0.07},
        {"target": "neck-scale-horiz-incr", "value": 0.10},
        {"target": "neck-scale-depth-incr", "value": 0.08},
        {"target": "measure-shoulder-dist-incr", "value": 0.07},
    ]
    TargetService.bulk_load_targets(body, target_stack)
    return target_stack


def add_cc0_bodypart(
    HumanService,
    body,
    mhclo_path: Path | None,
    asset_type: str,
    subdiv_levels: int = 0,
):
    if not mhclo_path or not mhclo_path.is_file():
        return None
    try:
        asset = HumanService.add_mhclo_asset(
            str(mhclo_path),
            body,
            asset_type=asset_type,
            subdiv_levels=subdiv_levels,
            material_type="GAMEENGINE",
            set_up_rigging=True,
            interpolate_weights=True,
            import_subrig=True,
            import_weights=True,
        )
        asset.name = f"Mercenary_Male_{asset_type}"
        return asset
    except Exception as exc:
        log(f"Optional {asset_type} preview asset failed: {exc}")
        return None


def aim_pose_bone(pose_bone: bpy.types.PoseBone, direction: Vector) -> None:
    """Rotate a pose bone around its head to point along an armature-space vector."""

    bpy.context.view_layer.update()
    desired = Vector(direction).normalized()
    current = (pose_bone.tail - pose_bone.head).normalized()
    rotation = current.rotation_difference(desired)
    pivot = pose_bone.head.copy()
    pose_bone.matrix = (
        Matrix.Translation(pivot)
        @ rotation.to_matrix().to_4x4()
        @ Matrix.Translation(-pivot)
        @ pose_bone.matrix
    )
    bpy.context.view_layer.update()


def pose_generated_rig_to_t(rig: bpy.types.Object) -> None:
    for side, direction in (("L", Vector((1, 0, 0))), ("R", Vector((-1, 0, 0)))):
        parent_control = rig.pose.bones[f"upper_arm_parent.{side}"]
        # Rigify uses 1.0 for FK in this generated rig.
        parent_control["IK_FK"] = 1.0
        for base_name in ("upper_arm_fk", "forearm_fk", "hand_fk"):
            aim_pose_bone(rig.pose.bones[f"{base_name}.{side}"], direction)


def pose_metarig_to_t(meta_rig: bpy.types.Object) -> None:
    """Keep the retained metarig useful for later Rigify regeneration."""

    bpy.ops.object.select_all(action="DESELECT")
    meta_rig.hide_viewport = False
    meta_rig.select_set(True)
    bpy.context.view_layer.objects.active = meta_rig
    bpy.ops.object.mode_set(mode="POSE")
    for side, direction in (("L", Vector((1, 0, 0))), ("R", Vector((-1, 0, 0)))):
        for base_name in ("upper_arm", "forearm", "hand"):
            pose_bone = meta_rig.pose.bones.get(f"{base_name}.{side}")
            if pose_bone:
                aim_pose_bone(pose_bone, direction)
    bpy.ops.pose.armature_apply(selected=False)
    bpy.ops.object.mode_set(mode="OBJECT")
    meta_rig.hide_viewport = True
    meta_rig.hide_render = True


def tpose_measurements(rig: bpy.types.Object) -> dict:
    result = {}
    for side in ("L", "R"):
        shoulder = rig.pose.bones[f"DEF-upper_arm.{side}"].head.copy()
        wrist = rig.pose.bones[f"DEF-hand.{side}"].tail.copy()
        span = wrist - shoulder
        result[side] = {
            "shoulder": list(shoulder),
            "wrist": list(wrist),
            "vertical_error_m": abs(span.z),
            "depth_error_m": abs(span.y),
            "arm_span_from_shoulder_m": span.length,
        }
    return result


def evaluated_mesh_stats(obj: bpy.types.Object) -> dict:
    depsgraph = bpy.context.evaluated_depsgraph_get()
    evaluated = obj.evaluated_get(depsgraph)
    mesh = evaluated.to_mesh()
    try:
        mesh.calc_loop_triangles()
        coordinates = [evaluated.matrix_world @ vertex.co for vertex in mesh.vertices]
        if coordinates:
            minimum = [min(co[i] for co in coordinates) for i in range(3)]
            maximum = [max(co[i] for co in coordinates) for i in range(3)]
        else:
            minimum = maximum = [0.0, 0.0, 0.0]
        return {
            "vertices": len(mesh.vertices),
            "polygons": len(mesh.polygons),
            "triangles": len(mesh.loop_triangles),
            "bbox_min": minimum,
            "bbox_max": maximum,
        }
    finally:
        evaluated.to_mesh_clear()


def look_at(obj: bpy.types.Object, target: Vector) -> None:
    direction = target - obj.location
    obj.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()


def add_area_light(name: str, location, energy: float, size: float, color) -> None:
    light_data = bpy.data.lights.new(name, type="AREA")
    light_data.energy = energy
    light_data.shape = "DISK"
    light_data.size = size
    light_data.color = color
    light_obj = bpy.data.objects.new(name, light_data)
    bpy.context.scene.collection.objects.link(light_obj)
    light_obj.location = location
    look_at(light_obj, Vector((0.0, 0.0, 1.05)))


def setup_preview_scene() -> bpy.types.Object:
    scene = bpy.context.scene
    # Blender 5.2 exposes Eevee as BLENDER_EEVEE; 4.x builds used
    # BLENDER_EEVEE_NEXT. Try the current identifier first and retain a fallback.
    try:
        scene.render.engine = "BLENDER_EEVEE"
    except TypeError:
        scene.render.engine = "BLENDER_EEVEE_NEXT"
    scene.render.resolution_x = 1024
    scene.render.resolution_y = 1024
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.film_transparent = False
    scene.view_settings.exposure = -0.7

    if scene.world is None:
        scene.world = bpy.data.worlds.new("MPFB_Preview_World")
    scene.world.use_nodes = True
    background = scene.world.node_tree.nodes.get("Background")
    background.inputs["Color"].default_value = (0.035, 0.03, 0.028, 1.0)
    background.inputs["Strength"].default_value = 0.12

    bpy.ops.mesh.primitive_plane_add(size=8.0, location=(0.0, 0.0, -0.012))
    floor = bpy.context.object
    floor.name = "MPFB_Preview_Floor"
    floor_material = bpy.data.materials.new("MPFB_Preview_Floor_Material")
    floor_material.use_nodes = True
    floor_shader = floor_material.node_tree.nodes.get("Principled BSDF")
    floor_shader.inputs["Base Color"].default_value = (0.055, 0.048, 0.043, 1.0)
    floor_shader.inputs["Roughness"].default_value = 0.82
    floor.data.materials.append(floor_material)

    add_area_light(
        "MPFB_Key",
        (-2.2, -2.6, 3.3),
        430.0,
        2.0,
        (1.0, 0.72, 0.55),
    )
    add_area_light(
        "MPFB_Fill",
        (2.6, -1.3, 2.0),
        150.0,
        2.4,
        (0.55, 0.68, 1.0),
    )
    add_area_light(
        "MPFB_Rim",
        (0.4, 2.0, 2.7),
        320.0,
        1.6,
        (1.0, 0.52, 0.32),
    )

    camera_data = bpy.data.cameras.new("MPFB_Preview_Camera")
    camera_data.type = "ORTHO"
    camera = bpy.data.objects.new("MPFB_Preview_Camera", camera_data)
    scene.collection.objects.link(camera)
    scene.camera = camera
    return camera


def render_preview(camera: bpy.types.Object, name: str, location, target, scale: float) -> Path:
    PREVIEW_DIR.mkdir(parents=True, exist_ok=True)
    camera.location = location
    camera.data.ortho_scale = scale
    look_at(camera, Vector(target))
    output_path = PREVIEW_DIR / name
    bpy.context.scene.render.filepath = str(output_path)
    bpy.ops.render.render(write_still=True)
    log(f"Rendered {output_path}")
    return output_path


def main() -> None:
    HumanService, TargetService, RigService, _ObjectService = load_mpfb_services()
    enable_rigify()
    clear_scene()
    preview_assets = extract_preview_assets()

    macro_profile = create_macro_profile(TargetService)
    body = HumanService.create_human(
        mask_helpers=True,
        detailed_helpers=True,
        extra_vertex_groups=True,
        feet_on_ground=True,
        scale=0.1,
        macro_detail_dict=macro_profile,
    )
    body.name = "Mercenary_Male_Body"
    body["character_profile"] = "late-30s sturdy male, neutral"
    body["target_height_m"] = 1.78
    body["expression"] = "neutral"

    face_targets = apply_reference_direction_face_targets(body, TargetService)

    skin_path = preview_assets.get("skin")
    if skin_path:
        try:
            HumanService.set_character_skin(
                str(skin_path),
                body,
                skin_type="GAMEENGINE",
                material_instances=False,
            )
        except Exception as exc:
            log(f"CC0 preview skin failed, using fallback: {exc}")
            create_fallback_skin_material(body)
    else:
        create_fallback_skin_material(body)

    subdivision = body.modifiers.new("LOD0_Subdivision", "SUBSURF")
    subdivision.subdivision_type = "CATMULL_CLARK"
    subdivision.levels = 1
    subdivision.render_levels = 1

    meta_rig = HumanService.add_builtin_rig(
        body, "rigify.human", import_weights=True
    )
    if meta_rig is None:
        raise RuntimeError("MPFB did not create the Rigify metarig")
    meta_rig.name = "Mercenary_Male_MetaRig"
    meta_rig.data.name = "Mercenary_Male_MetaRig"

    optional_assets = []
    for asset_type, key, subdiv in (
        ("Eyes", "eyes", 1),
        ("Hair", "hair", 0),
        ("Eyebrows", "brows", 0),
    ):
        asset = add_cc0_bodypart(
            HumanService,
            body,
            preview_assets.get(key),
            asset_type,
            subdiv_levels=subdiv,
        )
        if asset:
            optional_assets.append(asset)

    generated_rig = RigService.generate_rigify_rig(
        meta_rig,
        name="Mercenary_Male_Rig",
        meta_rig_action="keep",
    )
    if generated_rig is None:
        raise RuntimeError("Rigify rejected the MPFB metarig")
    generated_rig.name = "Mercenary_Male_Rig"
    generated_rig.data.name = "Mercenary_Male_Rig"

    pose_generated_rig_to_t(generated_rig)
    bpy.context.view_layer.update()
    pre_bake_tpose = tpose_measurements(generated_rig)
    for side, values in pre_bake_tpose.items():
        if values["vertical_error_m"] > 0.002:
            raise RuntimeError(f"{side} arm failed T-pose alignment: {values}")

    # Bake the visible T pose into both the deformed meshes and generated rig rest pose.
    # MPFB also recreates the armature modifiers after baking.
    RigService.apply_pose_as_rest_pose(generated_rig)
    pose_metarig_to_t(meta_rig)
    generated_rig.data.pose_position = "POSE"
    bpy.context.view_layer.update()

    post_bake_tpose = tpose_measurements(generated_rig)
    for side, values in post_bake_tpose.items():
        if values["vertical_error_m"] > 0.002:
            raise RuntimeError(f"{side} arm rest pose is not horizontal: {values}")

    generated_rig["rest_pose"] = "T-pose"
    generated_rig["rig_source"] = "MPFB 2.0.17 rigify.human"
    meta_rig["rest_pose"] = "T-pose"
    meta_rig.hide_viewport = True
    meta_rig.hide_render = True

    body_stats = evaluated_mesh_stats(body)
    asset_stats = {
        asset.name: evaluated_mesh_stats(asset) for asset in optional_assets
    }
    total_triangles = body_stats["triangles"] + sum(
        stats["triangles"] for stats in asset_stats.values()
    )

    camera = setup_preview_scene()
    front_path = render_preview(
        camera,
        "mpfb_base_tpose_front.png",
        (0.0, -4.0, 0.96),
        (0.0, 0.0, 0.96),
        2.05,
    )
    portrait_path = render_preview(
        camera,
        "mpfb_base_portrait.png",
        (0.0, -1.8, 1.64),
        (0.0, -0.02, 1.64),
        0.48,
    )

    bpy.ops.wm.save_as_mainfile(filepath=str(BLEND_PATH), check_existing=False)

    summary = {
        "status": "success",
        "blender_version": bpy.app.version_string,
        "mpfb_profile": macro_profile,
        "face_targets": face_targets,
        "expression": "neutral",
        "rest_pose": "T-pose",
        "body": {
            "base_vertices": len(body.data.vertices),
            "base_polygons": len(body.data.polygons),
            "uv_layers": [layer.name for layer in body.data.uv_layers],
            "vertex_groups": len(body.vertex_groups),
            "evaluated": body_stats,
        },
        "optional_cc0_preview_assets": asset_stats,
        "total_evaluated_triangles": total_triangles,
        "rig": {
            "generated_name": generated_rig.name,
            "generated_bones": len(generated_rig.data.bones),
            "metarig_name": meta_rig.name,
            "metarig_bones": len(meta_rig.data.bones),
            "tpose": post_bake_tpose,
        },
        "system_asset_zip": str(SYSTEM_ASSET_ZIP),
        "outputs": {
            "blend": str(BLEND_PATH),
            "front_preview": str(front_path),
            "portrait_preview": str(portrait_path),
        },
        "production_note": (
            "CC0 preview skin is 2K. Replace it with authored 4K PBR skin; "
            "custom clothing and reference-specific hair/beard remain separate work."
        ),
    }
    SUMMARY_PATH.write_text(
        json.dumps(summary, indent=2, ensure_ascii=False), encoding="utf-8"
    )
    log(f"Saved {BLEND_PATH}")
    log(f"Saved {SUMMARY_PATH}")
    log(f"Evaluated preview triangle total: {total_triangles:,}")


if __name__ == "__main__":
    main()
