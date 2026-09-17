from array import array
import json
from pathlib import Path

import bpy
from mathutils import Vector

root = Path("/Users/duq711gmail.com/Documents/ChatGPT/무시무시한 rpg")
staging = root / "asset-staging/blender_mercenary_crossbowman_game_ready"
preview = staging / "previews"
files = {
    "base": staging / "mercenary_crossbowman_game_ready_v13b.blend",
    "candidate": staging / "mercenary_crossbowman_game_ready_v14c.blend",
}


def look_at(obj, target):
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat("-Z", "Y").to_euler()


def render_masks(label, path):
    bpy.ops.wm.open_mainfile(filepath=str(path))
    scene = bpy.context.scene
    camera = scene.camera
    for name in ("Mercenary_Rigify_Rig_v4", "metarig_mercenary_v4", "PREVIEW_v4_Ground"):
        obj = bpy.data.objects.get(name)
        if obj:
            obj.hide_render = True
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.film_transparent = True
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.resolution_percentage = 100
    views = {
        "front": ((0.0, -5.2, 0.89), (0.0, 0.0, 0.89), "ORTHO", 2.06, 72),
        "back": ((0.0, 5.2, 0.89), (0.0, 0.0, 0.89), "ORTHO", 2.06, 72),
        "three_quarter": ((2.35, -3.15, 1.55), (0.0, 0.0, 1.0), "PERSP", None, 72),
    }
    outputs = {}
    for view, (location, target, camera_type, scale, lens) in views.items():
        camera.data.type = camera_type
        if camera_type == "ORTHO":
            camera.data.ortho_scale = scale
        else:
            camera.data.lens = lens
        camera.location = location
        look_at(camera, target)
        scene.render.resolution_x = 1200
        scene.render.resolution_y = 1200
        out = preview / f"diagnostic_v14c_mask_{label}_{view}.png"
        scene.render.filepath = str(out)
        bpy.ops.render.render(write_still=True)
        outputs[view] = out
    return outputs


outputs = {label: render_masks(label, path) for label, path in files.items()}
results = {}
for view in ("front", "back", "three_quarter"):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    image_a = bpy.data.images.load(str(outputs["base"][view]), check_existing=False)
    image_b = bpy.data.images.load(str(outputs["candidate"][view]), check_existing=False)
    count = image_a.size[0] * image_a.size[1]
    pixels_a = array("f", [0.0]) * (count * 4)
    pixels_b = array("f", [0.0]) * (count * 4)
    image_a.pixels.foreach_get(pixels_a)
    image_b.pixels.foreach_get(pixels_b)
    only_a = only_b = 0
    for index in range(3, count * 4, 4):
        alpha_a = pixels_a[index] > 0.5
        alpha_b = pixels_b[index] > 0.5
        if alpha_a and not alpha_b:
            only_a += 1
        elif alpha_b and not alpha_a:
            only_b += 1
    results[view] = {
        "pixels_base_only": only_a,
        "pixels_candidate_only": only_b,
        "symmetric_difference_pixels": only_a + only_b,
        "total_pixels": count,
    }

out = staging / "v14c_silhouette_mask_report.json"
out.write_text(json.dumps(results, indent=2), encoding="utf-8")
print("V14C_SILHOUETTE_MASKS", json.dumps(results, sort_keys=True))
print("V14C_SILHOUETTE_REPORT", out)
