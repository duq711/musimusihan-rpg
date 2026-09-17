"""Background Blender geometry QA, explicitly not a Godot screenshot.

First export with CAVE_QA_EXPORT_GEOMETRY=1 tests/run_headless_tests.sh cave_preview.
Then run Blender --background --factory-startup --threads 2 --python this_file.
The .glb is the actual generated cave. Only renderer-specific shading and light
response are approximated, so these pictures verify composition and geometry.
"""

import json
import math
import os
from pathlib import Path

import bpy
from mathutils import Vector


PROJECT = Path(__file__).resolve().parents[1]
OUTPUT = PROJECT / "artifacts" / "visual_qa" / "cave_offline"
METADATA = json.loads((OUTPUT / "metadata.json").read_text())
FAST_PREVIEW = os.environ.get("CAVE_OFFLINE_FAST") == "1"

bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)
bpy.ops.import_scene.gltf(filepath=str(OUTPUT / "cave_geometry.glb"))


def socket(node, name, value):
    if name in node.inputs:
        node.inputs[name].default_value = value


def source_color(value):
    # Godot's source_color shader uniforms are authored in sRGB. Blender node
    # colors are scene-linear, as are the factors already stored in the GLB.
    rgb = tuple(channel / 12.92 if channel <= 0.04045 else ((channel + 0.055) / 1.055) ** 2.4 for channel in value[:3])
    return rgb + (value[3],)


def rock_material(material):
    wet = material.name.startswith("Wet")
    material.use_nodes = True
    nodes = material.node_tree.nodes
    links = material.node_tree.links
    nodes.clear()
    output = nodes.new("ShaderNodeOutputMaterial")
    principled = nodes.new("ShaderNodeBsdfPrincipled")
    socket(principled, "Roughness", 0.46 if wet else 0.91)
    coord = nodes.new("ShaderNodeNewGeometry")
    noise = nodes.new("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = 3.8
    noise.inputs["Detail"].default_value = 4.0
    noise.inputs["Roughness"].default_value = 0.7
    links.new(coord.outputs["Position"], noise.inputs["Vector"])
    ramp = nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].position = 0.1
    ramp.color_ramp.elements[0].color = source_color((0.065, 0.073, 0.06, 1) if wet else (0.095, 0.075, 0.055, 1))
    ramp.color_ramp.elements[1].position = 0.9
    ramp.color_ramp.elements[1].color = source_color((0.43, 0.35, 0.255, 1))
    links.new(noise.outputs["Fac"], ramp.inputs["Fac"])
    links.new(ramp.outputs["Color"], principled.inputs["Base Color"])
    bump = nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.65
    bump.inputs["Distance"].default_value = 0.095
    links.new(noise.outputs["Fac"], bump.inputs["Height"])
    links.new(bump.outputs["Normal"], principled.inputs["Normal"])
    links.new(principled.outputs["BSDF"], output.inputs["Surface"])


for material in bpy.data.materials:
    if "CaveRockOfflineApproximation" in material.name:
        rock_material(material)
    elif material.name.startswith("CaveTriplanar_"):
        # Preserve the source texture while restoring world-space projection
        # that glTF cannot express from Godot's triplanar material.
        nodes = material.node_tree.nodes
        links = material.node_tree.links
        geometry = nodes.new("ShaderNodeNewGeometry")
        mapping = nodes.new("ShaderNodeVectorMath")
        mapping.operation = "SCALE"
        mapping.inputs["Scale"].default_value = 0.5
        links.new(geometry.outputs["Position"], mapping.inputs[0])
        for texture in [node for node in nodes if node.type == "TEX_IMAGE"]:
            texture.projection = "BOX"
            texture.projection_blend = 0.2
            links.new(mapping.outputs["Vector"], texture.inputs["Vector"])
    elif material.name.startswith("CaveWaterOfflineApproximation"):
        nodes = material.node_tree.nodes
        links = material.node_tree.links
        principled = next(node for node in nodes if node.type == "BSDF_PRINCIPLED")
        coord = nodes.new("ShaderNodeNewGeometry")
        wave = nodes.new("ShaderNodeTexNoise")
        wave.inputs["Scale"].default_value = 6.0
        wave.inputs["Detail"].default_value = 2.0
        links.new(coord.outputs["Position"], wave.inputs["Vector"])
        bump = nodes.new("ShaderNodeBump")
        bump.inputs["Strength"].default_value = 0.22
        bump.inputs["Distance"].default_value = 0.035
        links.new(wave.outputs["Fac"], bump.inputs["Height"])
        links.new(bump.outputs["Normal"], principled.inputs["Normal"])

flame_material = bpy.data.materials.new("OfflineFlameApproximation")
flame_material.use_nodes = True
flame = flame_material.node_tree.nodes.get("Principled BSDF")
socket(flame, "Base Color", (1.0, 0.34, 0.045, 1))
socket(flame, "Emission Color", (1.0, 0.24, 0.025, 1))
socket(flame, "Emission Strength", 5.0)

converted_torches = 0
converted_water_lights = 0
for obj in list(bpy.context.scene.objects):
    if obj.type != "LIGHT":
        continue
    # Godot may rename repeated sibling lights to generated node names. Classify
    # the actual exported light color so every torch gets the same conversion.
    if obj.data.color[0] > obj.data.color[2] * 1.2:
        converted_torches += 1
        obj.data.energy = 380.0
        obj.data.shadow_soft_size = 0.12
        bpy.ops.mesh.primitive_uv_sphere_add(segments=12, ring_count=8, radius=0.08, location=obj.matrix_world.translation)
        flame_obj = bpy.context.object
        flame_obj.name = "OfflineFlameApproximation"
        flame_obj.scale = (0.8, 0.8, 2.2)
        flame_obj.data.materials.append(flame_material)
    else:
        converted_water_lights += 1
        obj.data.energy = 18.0
        obj.data.shadow_soft_size = 1.0
assert converted_torches >= 30 and converted_water_lights == 2, (converted_torches, converted_water_lights)
print(f"OFFLINE LIGHT CONVERSION: {converted_torches} warm torches, {converted_water_lights} water fills", flush=True)

scene = bpy.context.scene
scene.render.engine = "CYCLES"
scene.cycles.device = "CPU"
scene.cycles.samples = 6 if FAST_PREVIEW else 24
scene.cycles.use_denoising = True
scene.cycles.max_bounces = 5
scene.render.threads_mode = "FIXED"
scene.render.threads = 2
scene.render.resolution_x = 960 if FAST_PREVIEW else 1280
scene.render.resolution_y = 540 if FAST_PREVIEW else 720
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = "PNG"
scene.view_settings.view_transform = "AgX"
scene.view_settings.exposure = 0.6
scene.world.use_nodes = True
scene.world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.20, 0.18, 0.16, 1)
scene.world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.07

# A mild volume gives the same spatial cue as the game's fog; its scattering
# implementation is intentionally treated as an approximation.
bpy.ops.mesh.primitive_cube_add(size=1, location=(0, 0, 5))
fog = bpy.context.object
fog.name = "OfflineFogApproximation"
fog.scale = (140, 148, 20)
fog.hide_render = FAST_PREVIEW
fog_material = bpy.data.materials.new("OfflineFogApproximation")
fog_material.use_nodes = True
fog_nodes = fog_material.node_tree.nodes
fog_nodes.clear()
fog_output = fog_nodes.new("ShaderNodeOutputMaterial")
volume = fog_nodes.new("ShaderNodeVolumePrincipled")
volume.inputs["Density"].default_value = 0.007
volume.inputs["Color"].default_value = (0.42, 0.38, 0.32, 1)
volume.inputs["Anisotropy"].default_value = 0.2
fog_material.node_tree.links.new(volume.outputs["Volume"], fog_output.inputs["Volume"])
fog.data.materials.append(fog_material)

camera_data = bpy.data.cameras.new("CaveGeometryReferenceCamera")
camera = bpy.data.objects.new("CaveGeometryReferenceCamera", camera_data)
scene.collection.objects.link(camera)
scene.camera = camera
camera_data.clip_start = 0.08
camera_data.clip_end = 200.0
camera_data.sensor_fit = "VERTICAL"
for label, light_type, energy, color in [
    ("OfflineCarriedTorchSpotApproximation", "SPOT", 550.0, (1.0, 0.64, 0.40)),
    ("OfflineCarriedTorchFillApproximation", "POINT", 300.0, (1.0, 0.49, 0.25)),
]:
    light_data = bpy.data.lights.new(label, light_type)
    light_data.energy = energy
    light_data.color = color
    light_data.shadow_soft_size = 0.12
    if light_type == "SPOT":
        light_data.spot_size = math.radians(120.0)
        light_data.spot_blend = 0.35
    carried_light = bpy.data.objects.new(label, light_data)
    scene.collection.objects.link(carried_light)
    carried_light.parent = camera
    carried_light.location = (-0.35, -0.2, -0.55)
scene.render.use_stamp = True
scene.render.use_stamp_date = False
scene.render.use_stamp_time = False
scene.render.use_stamp_render_time = False
scene.render.use_stamp_frame = False
scene.render.use_stamp_scene = False
scene.render.use_stamp_camera = False
scene.render.use_stamp_filename = False
scene.render.use_stamp_note = True
scene.render.stamp_note_text = "ACTUAL CAVE GEOMETRY  |  BLENDER REFERENCE  |  SHADING APPROXIMATE"
scene.render.stamp_font_size = 11


def godot_to_blender(value):
    return Vector((value[0], -value[2], value[1]))


requested_shot = os.environ.get("CAVE_OFFLINE_SHOT", "")
for shot in METADATA["shots"]:
    if requested_shot and shot["name"] not in requested_shot.split(","):
        continue
    camera.location = godot_to_blender(shot["position"])
    direction = godot_to_blender(shot["target"]) - camera.location
    camera.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    camera_data.angle = math.radians(shot["fov"])
    scene.render.filepath = str(OUTPUT / ("cave_" + shot["name"] + "_blender_reference.png"))
    bpy.ops.render.render(write_still=True)
    print("CAVE BLENDER GEOMETRY REFERENCE: " + scene.render.filepath, flush=True)

(OUTPUT / "README.txt").write_text(METADATA["notice"] + "\nThe three cameras and all cave meshes come from the game. No game actors are instantiated. The camera carries a warm spot and fill approximation of the player's lit torch. Fast previews omit volume scattering.\n")
