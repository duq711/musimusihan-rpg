"""Rebuild the supplied Medival outfit from its untouched Blender meshes.

Run on the user's Mac with:
  /Applications/Blender.app/Contents/MacOS/Blender --background --python build.py

The previous retargeting script cut the shirt and omitted the shoes.  This
script starts from the original .blend, bakes only its object transforms,
reconnects the supplied texture atlas, and makes the five garment materials
opaque.  No vertices, polygons, UVs, or fabric panels are removed or decimated.
"""

from __future__ import annotations

import hashlib
import json
import os
import subprocess
from pathlib import Path

import bpy
from mathutils import Matrix, Vector


OUT = Path(__file__).resolve().parent
ROOT = OUT.parent.parent
PREVIOUS_SOURCE = ROOT / "asset-staging/medival_cloth_20260923/source"
DOWNLOADS = Path.home() / "Downloads"
TEXTURES = OUT / "textures"
TEXTURES.mkdir(parents=True, exist_ok=True)

SOURCE_FILES = ("Medival.blend", "Medival.obj", "Medival.fbx", "Medival.mtl", "Textures.rar")
TEXTURE_FILES = (
    "16_DefaultMaterial_BaseColor.png",
    "16_DefaultMaterial_Normal.png",
    "16_DefaultMaterial_Roughness.png",
    "16_DefaultMaterial_Metallic.png",
    "16_DefaultMaterial_Opacity.png",
    "16_DefaultMaterial_Height.png",
)
SOURCE = DOWNLOADS if all((DOWNLOADS / name).exists() for name in SOURCE_FILES) else PREVIOUS_SOURCE


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


# Require the current Downloads uploads to match the already preserved originals.
# Cache digests so subsequent reporting does not re-read large cloud files.
source_hashes = {name: sha256(SOURCE / name) for name in SOURCE_FILES}
previous_hashes = (
    {name: sha256(PREVIOUS_SOURCE / name) for name in SOURCE_FILES}
    if all((PREVIOUS_SOURCE / name).exists() for name in SOURCE_FILES)
    else {}
)
if previous_hashes:
    mismatched = [name for name in SOURCE_FILES if source_hashes[name] != previous_hashes[name]]
    if mismatched:
        raise RuntimeError(f"New user files differ from preserved source: {mismatched}")

for name in TEXTURE_FILES:
    path = TEXTURES / name
    with path.open("wb") as stream:
        subprocess.run(["bsdtar", "-xOf", str(SOURCE / "Textures.rar"), name], stdout=stream, check=True)

bpy.ops.wm.open_mainfile(filepath=str(SOURCE / "Medival.blend"), load_ui=False)

for image in bpy.data.images:
    basename = os.path.basename(image.filepath)
    if basename in TEXTURE_FILES:
        image.filepath = str(TEXTURES / basename)
        image.reload()
        if basename != "16_DefaultMaterial_BaseColor.png":
            image.colorspace_settings.name = "Non-Color"
        # Blender 5.2 often reports has_data=False for lazily loaded images in
        # background mode; the exporter loads the on-disk PNG when needed.
        print("TEXTURE_RELINKED", basename, image.filepath, tuple(image.size))

SOURCE_OBJECTS = {
    "shirt": "Medival_ShirtUpper",
    "Pants": "Medival_Pants",
    "bend": "Medival_Belt",
    "boots_left": "Medival_Shoe_L",
    "Boots_right": "Medival_Shoe_R",
}
original_counts = {}
objects = []
for source_name, output_name in SOURCE_OBJECTS.items():
    obj = bpy.data.objects.get(source_name)
    if obj is None or obj.type != "MESH":
        raise RuntimeError(f"Expected source mesh is missing: {source_name}")
    original_counts[source_name] = (len(obj.data.vertices), len(obj.data.polygons))
    obj.data.transform(obj.matrix_world)
    obj.matrix_world = Matrix.Identity(4)
    obj.name = output_name
    obj.data.name = output_name + "Mesh"
    objects.append(obj)

    # The original atlas connects an opacity map to a shared BLEND material.
    # Its transparent areas expose empty garment interiors once the player body
    # is hidden.  Keep the source colour/normal/roughness maps and UVs, but give
    # each piece a fully opaque material for the clothing-only presentation.
    material = obj.data.materials[0].copy()
    material.name = output_name + "_Opaque"
    material.use_backface_culling = False
    # The deprecated blend_method property is still the glTF exporter's alpha
    # switch in Blender 5.2; explicitly request OPAQUE as well as disconnecting
    # the original atlas' opacity input.
    if hasattr(material, "blend_method"):
        material.blend_method = "OPAQUE"
    if material.use_nodes:
        # Source material uses the height atlas as 1-metre displacement.  The
        # rendered outfit is covered in harsh stippled noise at that scale;
        # glTF also has no matching displacement feature.  The colour texture
        # already carries fabric scratches, so remove displacement entirely.
        for node in material.node_tree.nodes:
            if node.type == "OUTPUT_MATERIAL":
                displacement = node.inputs.get("Displacement")
                if displacement:
                    for link in list(displacement.links):
                        material.node_tree.links.remove(link)
            elif node.type == "NORMAL_MAP":
                node.inputs["Strength"].default_value = 0.18
        for node in material.node_tree.nodes:
            if node.type == "BSDF_PRINCIPLED":
                alpha = node.inputs.get("Alpha")
                if alpha:
                    for link in list(alpha.links):
                        material.node_tree.links.remove(link)
                    alpha.default_value = 1.0
    obj.data.materials[0] = material

for source_name, output_name in SOURCE_OBJECTS.items():
    obj = bpy.data.objects[output_name]
    got = (len(obj.data.vertices), len(obj.data.polygons))
    if got != original_counts[source_name]:
        raise RuntimeError(f"Source topology changed for {source_name}: {original_counts[source_name]} -> {got}")

def bounds(obj):
    # bound_box can remain stale after baking the original 0.01 object scale.
    points = [obj.matrix_world @ vertex.co for vertex in obj.data.vertices]
    return [
        [round(min(p[i] for p in points), 6) for i in range(3)],
        [round(max(p[i] for p in points), 6) for i in range(3)],
    ]

report = {
    "source_directory": "Downloads" if SOURCE == DOWNLOADS else "asset-staging/medival_cloth_20260923/source",
    "source_files_sha256": source_hashes,
    "source_same_as_previous_staging": bool(previous_hashes),
    "method": "Original five source meshes; bake object transforms only; reconnect atlas; opaque materials; remove source 1m displacement and reduce normal-map strength.",
    "objects": [
        {
            "name": obj.name,
            "vertices": len(obj.data.vertices),
            "faces": len(obj.data.polygons),
            "bounds_blender_xyz": bounds(obj),
            "material": obj.data.materials[0].name,
        }
        for obj in objects
    ],
    "textures": list(TEXTURE_FILES),
    "rigged": False,
    "static_pose": True,
}

for obj in bpy.data.objects:
    obj.select_set(False)
for obj in objects:
    obj.select_set(True)
bpy.context.view_layer.objects.active = objects[0]

bpy.ops.file.pack_all()
bpy.ops.wm.save_as_mainfile(filepath=str(OUT / "Medival_Clean.blend"))
bpy.ops.export_scene.gltf(
    filepath=str(OUT / "Medival_Clean.glb"),
    export_format="GLB",
    use_selection=True,
    export_yup=True,
    export_texcoords=True,
    export_normals=True,
    export_materials="EXPORT",
)

with (OUT / "structure_report.json").open("w") as stream:
    json.dump(report, stream, indent=2)

# Render the exact exported geometry and material setup from multiple angles.
scene = bpy.context.scene
scene.render.engine = "BLENDER_EEVEE"
scene.render.resolution_x = 840
scene.render.resolution_y = 1040
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = "PNG"
scene.render.film_transparent = False
scene.world.color = (0.22, 0.22, 0.22)
scene.view_settings.view_transform = "AgX"

bpy.ops.object.camera_add(location=(0, 4, 1))
cam = bpy.context.object
scene.camera = cam
cam.data.type = "ORTHO"
cam.data.ortho_scale = 1.85
for location, power in (((-2, 3, 4), 850), ((2, -2, 3), 550)):
    bpy.ops.object.light_add(type="AREA", location=location)
    light = bpy.context.object
    light.data.energy = power
    light.data.shape = "DISK"
    light.data.size = 3.5
    light.rotation_euler = (Vector((0, 0, 0.9)) - light.location).to_track_quat("-Z", "Y").to_euler()

for label, location in (
    ("front", (0, 4, 0.9)),
    ("side", (4, 0, 0.9)),
    ("back", (0, -4, 0.9)),
    ("three_quarter", (3, 3, 0.9)),
):
    cam.location = location
    cam.rotation_euler = (Vector((0, 0, 0.8)) - cam.location).to_track_quat("-Z", "Y").to_euler()
    scene.render.filepath = str(OUT / f"preview_{label}.png")
    bpy.ops.render.render(write_still=True)
    print("RENDERED", scene.render.filepath)

print("CLEAN_ASSET_REPORT", json.dumps(report))
