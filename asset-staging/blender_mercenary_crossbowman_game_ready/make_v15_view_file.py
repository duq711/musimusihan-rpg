"""Create a presentation copy that opens centered and without auto-run prompts."""

from pathlib import Path

import bpy
from mathutils import Quaternion, Vector


ROOT = Path("/Users/duq711gmail.com/Documents/ChatGPT/무시무시한 rpg")
SOURCE = (
    ROOT
    / "asset-staging/blender_mercenary_crossbowman_game_ready"
    / "mercenary_crossbowman_game_ready_v15.blend"
)
OUTPUT = (
    ROOT
    / "asset-staging/blender_mercenary_crossbowman_game_ready"
    / "mercenary_crossbowman_game_ready_v15_view.blend"
)

bpy.ops.wm.open_mainfile(filepath=str(SOURCE))

# Keep the generated Rigify helper text for later manual use, but do not ask
# Blender to execute it automatically when this presentation copy is opened.
rig_ui = bpy.data.texts.get("mercenary_v4_rig_ui.py")
if rig_ui is not None:
    rig_ui.use_module = False

character_meshes = [
    obj
    for obj in bpy.context.scene.objects
    if obj.type == "MESH" and obj.get("part_category") is not None
]
for obj in bpy.context.scene.objects:
    if obj in character_meshes:
        obj.hide_viewport = False
        obj.hide_set(False)
    elif obj.type in {"CAMERA", "LIGHT"} or obj.type == "ARMATURE":
        obj.hide_viewport = True
        obj.hide_set(True)

bpy.ops.object.select_all(action="DESELECT")
bpy.context.view_layer.objects.active = None

# Blender's canonical front view looks along -Y with Z up.
front_rotation = Quaternion((0.70710678, 0.70710678, 0.0, 0.0))
for screen_name in ("Layout", "Modeling"):
    screen = bpy.data.screens.get(screen_name)
    if screen is None:
        continue
    for area in screen.areas:
        if area.type != "VIEW_3D":
            continue
        space = area.spaces.active
        region = space.region_3d
        region.view_perspective = "ORTHO"
        region.view_rotation = front_rotation
        region.view_location = Vector((0.0, 0.0, 0.90))
        region.view_distance = 2.15
        space.shading.type = "MATERIAL"
        space.overlay.show_extras = False
        space.overlay.show_relationship_lines = False
        space.clip_start = 0.01
        space.clip_end = 100.0

if bpy.context.window is not None:
    workspace = bpy.data.workspaces.get("Layout")
    if workspace is not None:
        bpy.context.window.workspace = workspace

bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT))
print("V15_VIEW_FILE", OUTPUT)
print("V15_VIEW_MESHES", len(character_meshes))
print("V15_VIEW_AUTORUN", None if rig_ui is None else rig_ui.use_module)
